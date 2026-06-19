module Shared.Model exposing (Model, DbStatus(..))

import NotebookEntry exposing (NotebookEntry)

type DbStatus
    = Checking
    | NeedsInstall
    | Installing String
    | Ready

type alias Model =
    { isAuthenticated : Bool
    , isSyncing : Bool
    , syncMessage : Maybe String
    , dbStatus : DbStatus
    , activeLearnQueue : List NotebookEntry
    }
