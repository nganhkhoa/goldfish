module Schema exposing (decodeToAST, CardAST, Block(..))

import Json.Decode as Decode
import Json.Encode as Encode

type Block
    = MainTitle String
    | SubTitle String
    | InlineTags (List String)
    | Meaning String
    | ActionRow (List String)
    | DictionaryEntry { pos : String, def : String }


type alias CardAST =
    { id : String
    , language : String
    , isSaved : Bool
    , layout : List Block -- The dynamic array of UI blocks
    }

koreanSchema : Decode.Decoder CardAST
koreanSchema =
    Decode.map6 (\id word maybeHanja meaning topik isSaved ->
        let
            -- 1. Start with the MainTitle
            baseLayout =
                [ MainTitle word ]

            -- 2. Conditionally append the SubTitle if Hanja exists
            layoutWithHanja =
                case maybeHanja of
                    Just hanja ->
                        [SubTitle hanja ] ++ baseLayout

                    Nothing ->
                        -- If undefined or null, just return the base layout
                        baseLayout

            -- 3. Append the remaining blocks
            tags = if topik == 0 then [] else [InlineTags [ "TOPIK " ++ String.fromInt topik ]]
            finalLayout = layoutWithHanja ++ tags ++ [ Meaning meaning ]
        in
        { id = id
        , language = "ko"
        , isSaved = isSaved
        , layout = finalLayout
        }
    )
        (Decode.field "id" Decode.string)
        (Decode.field "word" Decode.string)
        (Decode.maybe (Decode.field "hanja" Decode.string))
        (Decode.field "meaning" Decode.string)
        (Decode.field "topik" Decode.int)
        (Decode.field "isSaved" Decode.bool |> maybeBool)

chineseSchema : Decode.Decoder CardAST
chineseSchema =
    Decode.map7 (\id simplified traditional pinyin meaning hsk isSaved ->
        let
            hskstring = if hsk == 7 then "7-9" else String.fromInt hsk
        in
        { id = id
        , language = "cn"
        , isSaved = isSaved
        , layout =
            [ SubTitle ("【" ++ traditional ++ "】")
            , SubTitle ("[ " ++ pinyin ++ " ]")
            , MainTitle simplified
            , InlineTags [ "HSK " ++ hskstring ]
            , Meaning meaning
            ]
        }
    )
        (Decode.field "id" Decode.string)
        (Decode.field "simplified" Decode.string)
        (Decode.field "traditional" Decode.string)
        (Decode.field "pinyin" Decode.string)
        (Decode.field "meaning" Decode.string)
        (Decode.field "hsk" Decode.int)
        (Decode.field "isSaved" Decode.bool |> maybeBool)

type alias NestedMeaning =
    { pos : String
    , def : String
    }

meaningDecoder : Decode.Decoder NestedMeaning
meaningDecoder =
    Decode.map2 NestedMeaning
        (Decode.field "pos" Decode.string)
        (Decode.field "def" Decode.string)


japaneseSchema : Decode.Decoder CardAST
japaneseSchema =
    Decode.map6 (\id word furigana jlpt meaning isSaved ->
        let
            -- Format the integer into a nice tag pill
            tags =
                [ "JLPT N" ++ String.fromInt jlpt ]
        in
        { id = id
        , language = "jp"
        , isSaved = isSaved
        , layout =
            [ SubTitle furigana
            , MainTitle word
            , InlineTags tags
            , Meaning meaning
            ]
        }
    )
        (Decode.field "id" Decode.string)
        (Decode.field "word" Decode.string)
        (Decode.field "furigana" Decode.string)
        (Decode.field "jlpt" Decode.int)
        (Decode.field "meaning" Decode.string)
        (Decode.field "isSaved" Decode.bool |> maybeBool)

-- Helper for boolean fallbacks
maybeBool : Decode.Decoder Bool -> Decode.Decoder Bool
maybeBool decoder =
    Decode.maybe decoder |> Decode.map (Maybe.withDefault False)


decodeToAST : String -> Decode.Decoder CardAST
decodeToAST lang =
    case lang of
        "Korean" -> koreanSchema
        "ko" -> koreanSchema
        "Chinese" -> chineseSchema
        "cn" -> chineseSchema
        "Japanese" -> japaneseSchema
        "jp" -> japaneseSchema
        _    -> Decode.fail "Unknown language schema"

