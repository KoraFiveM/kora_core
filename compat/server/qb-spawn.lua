-- compat/server/qb-spawn.lua -- data-side compat for the real qb-spawn
-- resource's ONE server callback. The spawn-picker UI itself lives in
-- kora_multichar (merged there rather than as a separate qb-spawn resource --
-- see kora_multichar/spawn.lua), following the same split as
-- compat/server/qb-multicharacter.lua: kora_core owns legacy server-side DATA
-- compat regardless of which UI resource is installed.

QB.callback.register('qb-spawn:server:getOwnedHouses', function(src, citizenid)
    -- Real qb-spawn queries a `player_houses` table owned by qb-houses. No
    -- housing/apartments module exists anywhere in this codebase (grep
    -- confirmed at design time) -- there is nothing to query, so this always
    -- reports "no owned houses" rather than guessing at a schema that isn't
    -- there. Matches this codebase's own precedent for being honest about a
    -- compat layer's real limits (see kora_target/client/compat/ox-target.lua).
    return {}
end)
