module Pages.Goldfish.CharacterInput exposing (Model, Msg, page)

{-| Layout-first Chinese character input.

The 3,500-character local index is built by `scripts/build_character_index.py`
from Make Me a Hanzi IDS data.  It deliberately stores only the root layout
and its immediate visible components so a learner can browse by shape.
-}

import Dict exposing (Dict)
import Effect exposing (Effect)
import Html exposing (Html, button, div, h1, h2, h3, p, span, strong, text)
import Html.Attributes exposing (class, classList, disabled, title)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Layouts
import Page exposing (Page)
import Ports
import Route exposing (Route)
import Shared
import View exposing (View)


type Layout = LeftRight | TopBottom | Surround | ThreePart | Overlay


type alias Character =
    { hanzi : String, pinyin : String, gloss : String, layout : Layout, parts : List String }


type alias Model =
    { selectedLayout : Maybe Layout
    , selectedFamily : Maybe String
    , selectedParts : List String
    , characters : List Character
    , components : Dict String (List String)
    , loadFailed : Bool
    }


type Msg = ChooseLayout Layout | ChooseFamily String | ChoosePart String | ClearFamily | ClearParts | ClearPicker | GotCharacterIndex Decode.Value


page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = \_ ->
            ( { selectedLayout = Nothing, selectedFamily = Nothing, selectedParts = [], characters = [], components = Dict.empty, loadFailed = False }
            , Effect.sendCmd (Ports.requestCharacterIndex ())
            )
        , update = update
        , subscriptions = \_ -> Ports.receiveCharacterIndex GotCharacterIndex
        , view = view
        }
        |> Page.withLayout (\_ -> Layouts.Main {})


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ChooseLayout layout ->
            ( { model | selectedLayout = Just layout, selectedFamily = Nothing, selectedParts = [] }, Effect.none )
        ChooseFamily family ->
            ( { model | selectedFamily = Just family, selectedParts = [] }, Effect.none )
        ClearFamily ->
            ( { model | selectedFamily = Nothing, selectedParts = [] }, Effect.none )
        ChoosePart part ->
            let
                limit = partLimit model.selectedLayout
                updated =
                    if List.member part model.selectedParts then
                        List.filter ((/=) part) model.selectedParts
                    else
                        List.take (limit - 1) model.selectedParts ++ [ part ]
            in
            ( { model | selectedParts = updated, selectedFamily = Nothing }, Effect.none )
        ClearParts -> ( { model | selectedParts = [] }, Effect.none )
        ClearPicker -> ( { model | selectedLayout = Nothing, selectedFamily = Nothing, selectedParts = [] }, Effect.none )
        GotCharacterIndex value ->
            case Decode.decodeValue indexDecoder value of
                Ok index -> ( { model | characters = index.characters, components = index.components }, Effect.none )
                Err _ -> ( { model | loadFailed = True }, Effect.none )


type alias Index = { characters : List Character, components : Dict String (List String) }


indexDecoder : Decode.Decoder Index
indexDecoder = Decode.map2 Index (Decode.field "characters" (Decode.list characterDecoder)) (Decode.field "components" (Decode.dict (Decode.list Decode.string)))


characterDecoder : Decode.Decoder Character
characterDecoder =
    Decode.map5 Character
        (Decode.field "hanzi" Decode.string)
        (Decode.field "pinyin" Decode.string)
        (Decode.field "gloss" Decode.string)
        (Decode.field "layout" layoutDecoder)
        (Decode.field "parts" (Decode.list Decode.string))


layoutDecoder : Decode.Decoder Layout
layoutDecoder =
    Decode.string |> Decode.andThen (\value ->
        case layoutFromKey value of
            Just layout -> Decode.succeed layout
            Nothing -> Decode.fail "Unknown character layout")


layouts : List Layout
layouts = [ LeftRight, TopBottom, Surround, ThreePart, Overlay ]

layoutKey : Layout -> String
layoutKey layout = case layout of
    LeftRight -> "leftRight"
    TopBottom -> "topBottom"
    Surround -> "surround"
    ThreePart -> "threePart"
    Overlay -> "overlay"

layoutFromKey : String -> Maybe Layout
layoutFromKey key = List.filter (\layout -> layoutKey layout == key) layouts |> List.head

layoutName : Layout -> String
layoutName layout = case layout of
    LeftRight -> "Left + right"
    TopBottom -> "Top + bottom"
    Surround -> "Encloses"
    ThreePart -> "Three parts"
    Overlay -> "Overlaid / other"

layoutHint : Layout -> String
layoutHint layout = case layout of
    LeftRight -> "休 = 亻 + 木"
    TopBottom -> "想 = 相 + 心"
    Surround -> "国 = 囗 around 玉"
    ThreePart -> "湖 = 氵 + 古 + 月"
    Overlay -> "本 = 木 + 一"

layoutGlyph : Layout -> String
layoutGlyph layout = case layout of
    LeftRight -> "⿰"
    TopBottom -> "⿱"
    Surround -> "⿴"
    ThreePart -> "⿲"
    Overlay -> "⿻"

partLimit : Maybe Layout -> Int
partLimit selected =
    case selected of
        Just ThreePart -> 3
        _ -> 2


{-| Learners see common visual forms as one choice. For example, 月 is the
leader for both the moon 月 and the flesh-side form ⺼, so selecting 月 also
finds 脖. The stored IDS components remain unmodified for provenance.
-}
componentGroups : List ( String, List String )
componentGroups =
    [ ( "月", [ "月", "⺼" ] )
    , ( "水", [ "水", "氵" ] )
    , ( "手", [ "手", "扌" ] )
    , ( "心", [ "心", "忄", "⺗" ] )
    , ( "言", [ "言", "讠" ] )
    , ( "糸", [ "糸", "纟" ] )
    , ( "金", [ "金", "钅" ] )
    , ( "食", [ "食", "饣" ] )
    , ( "犬", [ "犬", "犭" ] )
    , ( "示", [ "示", "礻" ] )
    , ( "衣", [ "衣", "衤" ] )
    , ( "火", [ "火", "灬" ] )
    , ( "人", [ "人", "亻", "入" ] )
    , ( "刀", [ "刀", "刂" ] )
    , ( "邑", [ "邑", "阝" ] )
    , ( "辶", [ "辶", "⻌" ] )
    ]


componentLeader : String -> String
componentLeader part =
    componentGroups
        |> List.filter (\( leader, members ) -> List.member part members)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault part


componentMembers : String -> List String
componentMembers leader =
    componentGroups
        |> List.filter (\( groupLeader, _ ) -> groupLeader == leader)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault [ leader ]


componentLabel : String -> String
componentLabel leader =
    case componentMembers leader of
        [ _ ] ->
            leader

        members ->
            leader ++ "  ·  " ++ String.join " / " (List.filter ((/=) leader) members)


type alias Family =
    { name : String
    , components : List String
    }


leftRightFamilies : List Family
leftRightFamilies =
    [ { name = "People", components = [ "人", "女", "子", "老", "父", "母" ] }
    , { name = "Body", components = [ "月", "目", "耳", "口", "鼻", "骨" ] }
    , { name = "Water & weather", components = [ "水", "冫", "雨", "气", "风", "云" ] }
    , { name = "Plants & ground", components = [ "木", "艹", "土", "石", "禾", "米" ] }
    , { name = "Fire & light", components = [ "火", "日", "光", "电", "赤" ] }
    , { name = "Hands & tools", components = [ "手", "刀", "力", "金", "车", "弓" ] }
    , { name = "Walking & action", components = [ "足", "彳", "辶", "攵", "止", "走" ] }
    , { name = "Speech & thought", components = [ "言", "心", "口", "目", "见", "页" ] }
    , { name = "Animals", components = [ "犬", "马", "虫", "鱼", "鸟", "牛" ] }
    , { name = "Clothing & home", components = [ "糸", "衣", "食", "宀", "门", "广" ] }
    , { name = "Land & shapes", components = [ "阝", "山", "田", "王", "贝", "几" ] }
    , { name = "Ritual & writing", components = [ "示", "酉", "又", "巾", "革", "舟" ] }
    , { name = "Tools & forms", components = [ "舌", "歹", "矢", "工", "身", "立" ] }
    , { name = "Other common shapes", components = [ "欠", "令", "交", "且", "包", "匕" ] }
    ]


familiesFor : Layout -> List Family
familiesFor layout =
    case layout of
        LeftRight -> leftRightFamilies
        TopBottom ->
            [ { name = "Roofs & covers", components = [ "宀", "冖", "穴", "广", "⺮" ] }
            , { name = "Sky & small marks", components = [ "一", "亠", "⺍", "⺈", "小" ] }
            , { name = "Nature & places", components = [ "日", "山", "土", "田", "禾" ] }
            , { name = "People & actions", components = [ "人", "十", "大", "立", "夂" ] }
            , { name = "Other common tops", components = [ "丷", "八", "羊", "爫", "罒" ] }
            ]
        Surround ->
            [ { name = "Frames & doors", components = [ "囗", "门", "冂", "凵", "匚" ] }
            , { name = "Shelters & covers", components = [ "广", "尸", "厂", "疒", "户" ] }
            , { name = "Open sides & movement", components = [ "辶", "廴", "走", "勹", "几" ] }
            , { name = "Other enclosures", components = [ "匸", "虍", "戈", "麻", "羊" ] }
            ]
        ThreePart ->
            [ { name = "Lines & openings", components = [ "亠", "口", "辛", "⺍", "王" ] }
            , { name = "People & movement", components = [ "人", "彳", "手", "八", "弓" ] }
            ]
        Overlay ->
            [ { name = "Lines & openings", components = [ "一", "冂", "十", "口", "曰" ] }
            , { name = "People & objects", components = [ "行", "衣", "王", "禾", "刀" ] }
            , { name = "Small forms", components = [ "丿", "丷", "七", "千", "二" ] }
            ]


singleStrokeParts : List String
singleStrokeParts =
    [ "一", "丨", "丶", "丿", "乙", "亅", "⺄", "⺂", "⺁" ]


partAt : Int -> List String -> Maybe String
partAt index parts =
    List.drop index parts |> List.head


matches : Model -> Character -> Bool
matches model character =
    Just character.layout == model.selectedLayout
        && List.all identity
            (List.indexedMap
                (\index selected ->
                    partAt index character.parts
                        |> Maybe.map componentLeader
                        |> (==) (Just selected)
                )
                model.selectedParts
            )

results : Model -> List Character
results model =
    case model.selectedLayout of
        Nothing ->
            []

        Just _ ->
            if List.isEmpty model.selectedParts then
                []
            else
                List.filter (matches model) model.characters


availableParts : Model -> Layout -> List String
availableParts model layout =
    let
        slot = List.length model.selectedParts
        allowedByFamily =
            case model.selectedFamily of
                Nothing ->
                    []

                Just familyName ->
                    familiesFor layout
                        |> List.filter (\family -> family.name == familyName)
                        |> List.head
                        |> Maybe.map .components
                        |> Maybe.withDefault []
        parts =
            model.characters
                |> List.filter (\character -> Just character.layout == Just layout)
                |> List.filter (\character ->
                    List.all identity
                        (List.indexedMap
                            (\index selected ->
                                partAt index character.parts
                                    |> Maybe.map componentLeader
                                    |> (==) (Just selected)
                            )
                            model.selectedParts
                        )
                )
                |> List.filterMap (.parts >> partAt slot)
    in
    parts
        |> List.filter (\part -> not (List.member part singleStrokeParts))
        |> List.map componentLeader
        |> unique
        |> List.filter (\part -> List.isEmpty allowedByFamily || List.member part allowedByFamily)


unique : List String -> List String
unique items =
    List.foldl (\item seen -> if List.member item seen then seen else seen ++ [ item ]) [] items


view : Model -> View Msg
view model =
    { title = "Character picker | Goldfish"
    , body =
        [ div [ class "character-picker-page" ]
            [ div [ class "character-picker-heading" ]
                [ div []
                    [ p [ class "eyebrow" ] [ text "Chinese input · layout first" ]
                    , h1 [] [ text "Find a character by how it is built" ]
                    , p [ class "character-picker-intro" ] [ text "Choose the shape first, then tap the pieces you recognize. Similar-looking forms are grouped under one familiar leader, so you do not need to know a formal radical name." ]
                    ]
                , button [ class "picker-reset", onClick ClearPicker ] [ text "Clear all" ]
                ]
            , div [ class "picker-progress" ]
                [ progressStep "1" "Choose layout" (model.selectedLayout /= Nothing), span [ class "progress-line" ] []
                , progressStep "2" "Choose pieces" (not (List.isEmpty model.selectedParts)), span [ class "progress-line" ] []
                , progressStep "3" "Pick character" (not (List.isEmpty (results model))) ]
            , sectionBlock "1. What is the character's layout?" "Start with the broad visual pattern." (div [ class "layout-grid" ] (List.map (layoutButton model.selectedLayout) layouts))
            , viewPartStep model
            , viewResults model
            , div [ class "picker-source-note" ]
                [ h3 [] [ text "3,500-character local index" ]
                , p [] [ text "The index prioritizes characters appearing in the included HSK word list, then fills to 3,500 with usable decompositions. It is generated from Make Me a Hanzi dictionary data (LGPL-3.0-or-later) and loads locally." ] ]
            ] ] }

sectionBlock heading description content = div [ class "picker-section" ] [ h2 [] [ text heading ], p [ class "picker-section-description" ] [ text description ], content ]
progressStep number label complete = div [ classList [ ( "progress-step", True ), ( "complete", complete ) ] ] [ span [ class "progress-number" ] [ text number ], text label ]

layoutButton selected layout = button [ classList [ ( "layout-choice", True ), ( "selected", selected == Just layout ) ], onClick (ChooseLayout layout) ] [ span [ class "layout-symbol" ] [ text (layoutGlyph layout) ], span [ class "layout-copy" ] [ span [ class "layout-name" ] [ text (layoutName layout) ], span [ class "layout-hint" ] [ text (layoutHint layout) ] ] ]

viewPartStep : Model -> Html Msg
viewPartStep model = case model.selectedLayout of
    Nothing -> div [ class "picker-section picker-section-muted" ] [ h2 [] [ text "2. Which pieces can you see?" ], p [] [ text "Choose a layout to reveal relevant components." ] ]
    Just layout ->
        let palette = availableParts model layout
            labels = positionLabels layout
        in sectionBlock "2. Select each position" ("Choose the left/top/outer piece first, then the next position. One-stroke pieces are inferred rather than shown. A leader such as 月 also searches its similar side-form ⺼.") <|
            div []
                [ div [ class "chosen-parts" ] (List.indexedMap (\index label -> chosenPart label (List.drop index model.selectedParts |> List.head)) labels)
                , div [ class "picker-actions" ]
                    [ button [ class "clear-parts", onClick ClearParts, disabled (List.isEmpty model.selectedParts) ] [ text "Clear pieces" ]
                    , if model.selectedFamily /= Nothing then button [ class "clear-parts", onClick ClearFamily ] [ text "Change family" ] else text ""
                    ]
                , if List.isEmpty model.selectedParts && model.selectedFamily == Nothing then
                    viewFamilies (familiesFor layout)
                  else if List.isEmpty model.characters && not model.loadFailed then
                    p [ class "picker-loading" ] [ text "Loading 3,500 characters…" ]
                  else
                    div [ class "part-grid" ] (List.map (partButton model) palette)
                ]

positionLabels : Layout -> List String
positionLabels layout =
    case layout of
        LeftRight -> [ "Left", "Right" ]
        TopBottom -> [ "Top", "Bottom" ]
        Surround -> [ "Outer", "Inner" ]
        ThreePart -> [ "Left", "Middle", "Right" ]
        Overlay -> [ "Base", "Overlaid" ]


viewFamilies : List Family -> Html Msg
viewFamilies families =
    div [ class "family-grid" ] (List.map familyButton families)


familyButton : Family -> Html Msg
familyButton family =
    button [ class "family-choice", onClick (ChooseFamily family.name) ]
        [ strong [] [ text family.name ]
        , span [ class "family-components" ] [ text (String.join "  " family.components) ]
        ]


chosenPart label part =
    div [ class "chosen-part" ]
        [ span [] [ text label ]
        , strong [] [ text (part |> Maybe.map componentLabel |> Maybe.withDefault "—") ]
        ]
partButton model part =
    button
        [ classList [ ( "part-choice", True ), ( "selected", List.member part model.selectedParts ), ( "grouped", List.length (componentMembers part) > 1 ) ]
        , onClick (ChoosePart part)
        , title ("Select the " ++ part ++ " component group")
        ]
        [ span [ class "part-leader" ] [ text part ]
        , if List.length (componentMembers part) > 1 then span [ class "part-variants" ] [ text (String.join "/" (List.filter ((/=) part) (componentMembers part))) ] else text ""
        ]

viewResults : Model -> Html Msg
viewResults model = case model.selectedLayout of
    Nothing -> div [ class "picker-section picker-section-muted" ] [ h2 [] [ text "3. Matching characters" ], p [] [ text "Your matches will appear here." ] ]
    Just _ ->
        if List.isEmpty model.selectedParts then
            sectionBlock "3. Choose the character" "Select at least one piece to see matches." <|
                div [ class "no-character-results" ] [ text "The picker does not list every character until you choose a component." ]
        else
            let found = results model
                description = if model.loadFailed then "The local character index could not load." else if List.isEmpty model.characters then "Loading index…" else if List.isEmpty found then "No matches. Clear a piece or choose another layout." else String.fromInt (List.length found) ++ " matching character(s)"
            in sectionBlock "3. Choose the character" description <| if List.isEmpty found then div [ class "no-character-results" ] [ text "Try selecting fewer pieces, or use Clear pieces." ] else div [ class "character-results" ] (List.map characterCard found)

characterCard character = button [ class "character-result" ] [ span [ class "result-hanzi" ] [ text character.hanzi ], span [ class "result-details" ] [ strong [] [ text character.pinyin ], span [] [ text character.gloss ], span [ class "result-parts" ] [ text (String.join "  +  " character.parts) ] ] ]
