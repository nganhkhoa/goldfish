module Helper exposing (..)

import Random

shuffleGenerator : List a -> Random.Generator (List a)
shuffleGenerator list =
    Random.list (List.length list) (Random.float 0 1)
        |> Random.map (\floats ->
            List.map2 Tuple.pair floats list
                |> List.sortBy Tuple.first
                |> List.map Tuple.second
        )
