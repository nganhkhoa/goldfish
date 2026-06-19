module Shared.Msg exposing (Msg(..))

import NotebookEntry exposing (NotebookEntry)

type Msg
    = AuthStatusChanged Bool
    | SyncStatusReceived String
    | DbStatusChanged Bool
    | InstallProgressMsg String
    | StartInstallClicked
    | SetLearnQueue (List NotebookEntry)
