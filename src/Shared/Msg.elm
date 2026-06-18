module Shared.Msg exposing (Msg(..))

type Msg
    = AuthStatusChanged Bool
    | SyncStatusReceived String
    | DbStatusChanged Bool
    | InstallProgressMsg String
    | StartInstallClicked
