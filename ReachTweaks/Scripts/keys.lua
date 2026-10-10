-- Keyboard shortcuts polled from the game-thread tick.
-- UE4SS runs RegisterKeyBind callbacks on its own thread, at the same time
-- as our game-thread Lua (main loop, hooks), on the same Lua state: that
-- crashed the game inside UE4SS when pressing F5-F8. Polling with
-- APlayerController::IsInputKeyDown keeps all Lua on the game thread.
-- As before, the game window on the PC must have focus.
local Util = require("util")

local Keys = {}

local binds = {}   -- {name, fn, down}

function Keys.Bind(name, fn)
    binds[#binds + 1] = { name = name, fn = fn, down = false }
end

function Keys.Tick(pc)
    for _, b in ipairs(binds) do
        local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(b.name) }) end)
        down = ok and down == true
        if down and not b.down then Util.SafeCall(b.fn) end
        b.down = down
    end
end

return Keys
