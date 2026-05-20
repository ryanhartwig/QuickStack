--- QuickStack: Label matching module
--- Token-prefix scoring with word-coverage and CJK character tiebreaker

local matching = {}

--- Score how well a locker label matches an item's display name
--- Returns 0 (no match) or positive score (higher = better match)
--- Label is comma-separated groups (OR), each group is space-separated tokens (AND)
--- Each token must be a case-insensitive prefix of a distinct word in the display name
--- Score = word coverage + character coverage tiebreaker
--- The tiebreaker ensures "铜线" beats "铜" for item "铜线" (CJK has no word spaces)
function matching.scoreLockerMatch(label, displayName)
    local nameWords = {}
    local totalNameChars = 0
    for word in displayName:lower():gmatch("%S+") do
        table.insert(nameWords, word)
        totalNameChars = totalNameChars + #word
    end
    if #nameWords == 0 then return 0 end

    local bestScore = 0

    for part in label:gmatch("[^,]+") do
        local tokens = {}
        for token in part:lower():gmatch("%S+") do
            if not token:match("^%d+$") then  -- skip pure numbers (locker identifiers like "1", "2")
                table.insert(tokens, token)
            end
        end
        if #tokens == 0 then goto nextPart end

        -- Each token must prefix-match a distinct word
        local usedWords = {}
        local matched = 0
        local matchedTokenChars = 0
        for _, token in ipairs(tokens) do
            for j, word in ipairs(nameWords) do
                if not usedWords[j] and word:sub(1, #token) == token then
                    usedWords[j] = true
                    matched = matched + 1
                    matchedTokenChars = matchedTokenChars + #token
                    break
                end
            end
        end

        -- All tokens must match for this group to count
        if matched == #tokens then
            -- Word coverage is the primary score (0 to 1.0)
            -- Character coverage is a tiebreaker (adds 0 to 0.01)
            local score = (matched / #nameWords)
                + (matchedTokenChars / totalNameChars) * 0.01
            if score > bestScore then bestScore = score end
        end

        ::nextPart::
    end

    return bestScore
end

return matching
