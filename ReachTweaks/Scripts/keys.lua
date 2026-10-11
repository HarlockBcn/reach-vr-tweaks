-- Keyboard shortcuts polled from the game-thread tick.
-- UE4SS runs RegisterKeyBind callbacks on its own thread, at the same time
-- as our game-thread Lua (main loop, hooks), on the same Lua state: that
-- crashed the game inside UE4SS when pressing F5-F8. Polling with
-- APlayerController::IsInputKeyDown keeps all Lua on the game thread.
-- As before, the game window on the PC must have focus.
local Util = require("util")

local Keys = {}

local binds = {}   -- {name, fn, down}

local POLL_MS = 30   -- a key press lasts much longer than this
local sinceMs = 0

function Keys.Bind(name, fn)
    binds[#binds + 1] = { name = name, fn = fn, down = false }
end

function Keys.Tick(pc, dtMs)
    sinceMs = sinceMs + (dtMs or POLL_MS)
    if sinceMs < POLL_MS then return end
    sinceMs = 0
    for _, b in ipairs(binds) do
        -- FKey built once per key (an FName is a plain value, not a UObject)
        b.key = b.key or { KeyName = FName(b.name) }
        local ok, down = pcall(function() return pc:IsInputKeyDown(b.key) end)
        down = ok and down == true
        if down and not b.down then Util.SafeCall(b.fn) end
        b.down = down
    end
end

return Keys
