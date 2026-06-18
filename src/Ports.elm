port module Ports exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode

-- INBOUND
port dbStatusReceived : (Bool -> msg) -> Sub msg
port installProgress : (String -> msg) -> Sub msg

-- OUTBOUND
port startDbInstall : () -> Cmd msg

-- SEARCH
port requestSearch : Encode.Value -> Cmd msg
port receiveSearchResults : (Decode.Value -> msg) -> Sub msg

-- NOTEBOOK READ
port requestNotebook : () -> Cmd msg
port receiveNotebook : (Decode.Value -> msg) -> Sub msg

-- NOTEBOOK MUTATION (Add, Remove, Update)
port mutateNotebook : Encode.Value -> Cmd msg

-- OUTBOUND (Elm -> JS)
port requestSignIn : () -> Cmd msg
port requestSignOut : () -> Cmd msg
port requestSync : () -> Cmd msg

-- INBOUND (JS -> Elm)
-- True if logged in, False if logged out
port authStatusChanged : (Bool -> msg) -> Sub msg

-- Sends back a status message (e.g., "Synced successfully", "Downloaded new data")
port syncStatus : (String -> msg) -> Sub msg
