module Learn.Engine exposing (..)

import NotebookEntry exposing (NotebookEntry)
import Time

import Random
import Random.List

type alias Session =
    { queue : List NotebookEntry
    , completed : List NotebookEntry
    , current : Maybe NotebookEntry
    }

type PackFilter
    = Due
    | New
    | All

parseFilter : String -> PackFilter
parseFilter str =
    case str of
        "due" -> Due
        "new" -> New
        _     -> All

initSession : Int -> Random.Seed -> List NotebookEntry -> PackFilter -> Session
initSession now seed entries filterType =
    let
        -- _ = Debug.log "=== Engine Init ===" ""
        -- _ = Debug.log "Active Filter" filterType
        -- _ = Debug.log "Current Time (ms)" now
        -- _ = Debug.log "Entries BEFORE filter" (List.length entries)

        filteredQueue = case filterType of
            Due -> List.filter (\e -> e.nextReview == 0 || e.nextReview <= now) entries
            New -> List.filter (\e -> e.nextReview == 0) entries
            All -> entries

        -- _ = List.map (\e -> 
        --         Debug.log ("Card ID " ++ String.fromInt e.notebookId) 
        --             ("nextReview: " ++ String.fromInt e.nextReview ++ " <= now? " ++ (if e.nextReview <= now then "True" else "False"))
        --     ) filteredQueue

        ( finalDeck, _ ) = Random.step (Random.List.shuffle filteredQueue) seed

        -- _ = Debug.log "Entries AFTER filter" (List.length finalDeck)
    in
    { queue = finalDeck
    , completed = []
    , current = List.head finalDeck
    }

processAnswer : Int -> Int -> Session -> Session
processAnswer now quality session =
    case session.current of
        Nothing -> session
        Just card ->
            let
                graded = evaluateCard now quality card
                -- Ensure this is actually dropping the head!
                remaining = List.drop 1 session.queue
            in
            { queue = remaining
            , completed = graded :: session.completed
            , current = List.head remaining -- This SHOULD be the next card
            }

evaluateCard : Int -> Int -> NotebookEntry -> NotebookEntry
evaluateCard currentTimeMs quality entry =
    let
        -- 1. Calculate the new Ease Factor (Standard SM-2 Formula)
        newEase =
            max 1.3 (entry.easeFactor + (0.1 - (5.0 - toFloat quality) * (0.08 + (5.0 - toFloat quality) * 0.02)))

        -- 2. Calculate the new Interval (in days)
        newInterval =
            if quality < 3 then
                -- Failed: Reset interval back to 1 day
                1.0
            else if entry.interval == 0.0 then
                -- First successful review
                1.0
            else if entry.interval == 1.0 then
                -- Second successful review
                6.0
            else
                -- Subsequent reviews: Multiply by Ease
                entry.interval * newEase

        -- 3. Apply your 3-Month (90 Day) Mastery Threshold
        isMastered =
            newInterval >= 90.0

        -- 4. Map the math back to your discrete UI state
        finalMemoryLevel =
            if isMastered then
                2 -- Mastered (Graduated from active daily reviews)
            else if newInterval > 1.0 then
                1 -- Actively Learning
            else
                0 -- Unlearned / Needs heavy review

        -- Calculate the exact millisecond timestamp for the next review
        msInADay = 86400000
        newNextReview =
            currentTimeMs + round (newInterval * msInADay)

    in
    { entry
        | interval = newInterval
        , easeFactor = newEase
        , nextReview = newNextReview
        , memoryLevel = finalMemoryLevel
    }

