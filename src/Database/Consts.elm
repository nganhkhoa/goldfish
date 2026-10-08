module Database.Consts exposing (..)

type Language
  = Chinese
  | Korean
  | Japanese

short_language_string : Language -> String
short_language_string language =
  case language of
    Chinese -> "cn"
    Korean -> "ko"
    Japanese -> "jp"

long_language_string : Language -> String
long_language_string language =
  case language of
    Chinese -> "Chinese"
    Korean -> "Korean"
    Japanese -> "Japanese"

