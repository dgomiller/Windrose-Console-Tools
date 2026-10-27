--[[
 Windrose Console Tools
 A small, standalone set of "rf"-prefixed console commands for testing/debugging in Windrose --
 spawning a class for a quick look, inspecting whatever you're aiming at, and basic utility
 toggles (no-clip, freeze AI). Independent of (and safe to run alongside) Living Base/Living Base
 Enhanced -- this mod does not touch persist.txt, does not restore anything on world load, and
 does not share any state with LBE. Everything this mod spawns is session-only: close the game (or
 despawn it yourself with rfdespawn) and it's gone, nothing is saved.

 If you want the full creative/building toolkit (hundreds of placeable items, a persistent base
 that survives reloads, NPC customization, photo mode, etc.) that's what Living Base Enhanced is
 for -- this mod is deliberately just the bare debug/testing commands.
]]

local UEHelpers = require("UEHelpers")

local MOD_NAME = "[WindroseConsoleTools]"

local function log(msg)
    print(string.format("%s %s\n", MOD_NAME, tostring(msg)))
end

----------------------------------------------------------------------------------------------
-- Shared command registry, for rfhelp
----------------------------------------------------------------------------------------------

local RF_COMMANDS = {}
local function registerCmdInfo(name, usage, desc)
    RF_COMMANDS[#RF_COMMANDS + 1] = { name = name, usage = usage or name, desc = desc or "" }
end

----------------------------------------------------------------------------------------------
-- Shared targeting cache -- what rftarget last aimed at. rftargetdata, rfgettargetfuncs, and
-- rfnoai all read from this ONE slot, the same "probe, then act" two-step every command in this
-- mod uses: aim with rftarget first, then run whichever follow-up command you need, as many
-- times as you like, until you rftarget something else.
----------------------------------------------------------------------------------------------

local RF = { lastProbed = nil, spawned = {} }

local function getGameplayStatics()
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if gs and gs:IsValid() then return gs end
    return nil
end

-- Finds the nearest actor within maxDist of where the player's camera is looking. This is the
-- same "aim and pick" approach used by every targeting command in this mod (rftarget) --
-- deliberately simple (no lock/pin feature, unlike LBE's equivalent) since this is meant to be a
-- lightweight tool: aim, run a command, re-aim if you want something else.
local function findNearestActorInFront(maxDist)
    maxDist = maxDist or 400.0
    local pc = UEHelpers.GetPlayerController()
    if not (pc and pc:IsValid()) then return nil end
    local pawn = pc.Pawn
    if not (pawn and pawn:IsValid()) then return nil end
    local camX, camY, camZ, cfx, cfy, cfz
    pcall(function()
        local cam = pc.PlayerCameraManager
        local loc = cam and cam:IsValid() and cam:GetCameraLocation()
        local rot = cam and cam:IsValid() and cam:GetCameraRotation()
        if loc then camX, camY, camZ = loc.X, loc.Y, loc.Z end
        if rot then
            local yaw, pitch = math.rad(rot.Yaw), math.rad(rot.Pitch)
            local cp = math.cos(pitch)
            cfx, cfy, cfz = cp * math.cos(yaw), cp * math.sin(yaw), math.sin(pitch)
        end
    end)
    if not camX then
        local loc = pawn:K2_GetActorLocation()
        local rot = pawn:K2_GetActorRotation()
        camX, camY, camZ = loc.X, loc.Y, loc.Z
        local yaw = math.rad(rot.Yaw)
        cfx, cfy, cfz = math.cos(yaw), math.sin(yaw), 0.0
    end
    local minViewDot = 0.90
    local bestActor, bestDist = nil, nil
    pcall(function()
        local world = UEHelpers.GetWorld()
        local allActors = FindAllOf("Actor")
        if not allActors then return end
        for _, a in pairs(allActors) do
            if a and a:IsValid() and a ~= pawn then
                local ok, loc = pcall(function() return a:K2_GetActorLocation() end)
                if ok and loc then
                    local dx, dy, dz = loc.X - camX, loc.Y - camY, loc.Z - camZ
                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if dist > 1.0 and dist <= maxDist then
                        local dot = (dx * cfx + dy * cfy + dz * cfz) / dist
                        if dot >= minViewDot and (not bestDist or dist < bestDist) then
                            bestActor, bestDist = a, dist
                        end
                    end
                end
            end
        end
    end)
    return bestActor, bestDist
end

----------------------------------------------------------------------------------------------
-- rfhelp
----------------------------------------------------------------------------------------------

-- Wraps a long line of text to a given width, breaking on spaces -- without this, a detailed
-- description printed as one line runs off the side of the console window instead of being
-- readable. Returns a table of lines.
local function wrapText(text, width)
    width = width or 100
    local lines = {}
    local line = ""
    for word in tostring(text):gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. " " .. word
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfhelp", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local sorted = {}
            for _, c in ipairs(RF_COMMANDS) do sorted[#sorted + 1] = c end
            table.sort(sorted, function(a, b) return a.name < b.name end)
            local query = Parameters and Parameters[1]
            if query and query:lower() == "find" then
                local words = {}
                for i = 2, #Parameters do
                    local w = tostring(Parameters[i] or ""):lower()
                    if w ~= "" then words[#words + 1] = w end
                end
                if #words == 0 then
                    say("usage: rfhelp find <word> [more words] -- lists every command whose name, usage, or description contains all the given words.")
                    return true
                end
                local hits = 0
                for _, c in ipairs(sorted) do
                    local haystack = (c.name .. " " .. c.usage .. " " .. c.desc):lower()
                    local allMatch = true
                    for _, w in ipairs(words) do
                        if not haystack:find(w, 1, true) then allMatch = false; break end
                    end
                    if allMatch then
                        hits = hits + 1
                        say(c.name)
                    end
                end
                say(string.format("(%d match(es)) -- run 'rfhelp <command>' for details on one.", hits))
                return true
            end
            -- rfhelp <commandname> -- exact-match lookup, same as LBE's own lbhelp <command>:
            -- prints just that one command's full usage + detailed description, instead of the
            -- whole list. The description is WORD-WRAPPED (lbhelp itself never needed this --
            -- its descriptions are dev-facing one-liners; these are deliberately longer/more
            -- detailed since this mod is meant for other people, not just internal shorthand) --
            -- without it, a long description printed as one line runs off the side of the
            -- console window.
            if query and query ~= "" then
                local ql = query:lower()
                local found = nil
                for _, c in ipairs(sorted) do
                    if c.name:lower() == ql then found = c; break end
                end
                if not found then
                    say("rfhelp: no command named '" .. query .. "' -- run rfhelp with no arguments for the full list, or rfhelp find <word> to search.")
                    return true
                end
                say(found.usage)
                if found.desc and found.desc ~= "" then
                    for _, line in ipairs(wrapText(found.desc, 100)) do say(line) end
                end
                return true
            end
            say(string.format("Windrose Console Tools -- %d command(s). Run 'rfhelp <command>' for its syntax/description, or 'rfhelp find <word>' to search.", #sorted))
            for _, c in ipairs(sorted) do
                say("  " .. c.name)
            end
            return true
        end)
    end)
    log("Console command registered: rfhelp [<command> | find <word> [more words]]")
else
    log("RegisterConsoleCommandHandler is missing in this UE4SS build -- none of this mod's commands are available. Check that you are on a UE4SS build with console command support, same requirement Living Base/LBE have.")
end

----------------------------------------------------------------------------------------------
-- rftarget / rftargetdata / rfgettargetfuncs -- aim-and-inspect, three steps that share one cache
----------------------------------------------------------------------------------------------

-- Walks an object's own declared properties, up its whole class hierarchy, printing name=value
-- for each. KNOWN CRASH GUARD: walking either of the game's "interaction target" component
-- classes' own property list crashes the game outright (an uncatchable native crash, confirmed
-- live) -- those two classes are skipped with a message instead of being walked.
local function dumpObjectProperties(obj, tag, say)
    local cls
    pcall(function() cls = obj:GetClass() end)
    while cls and cls:IsValid() do
        local className = "?"
        pcall(function() className = cls:GetFName():ToString() end)
        if className == "R5PrimitiveInteractionTargetComponent" or className == "R5CommonInteractionTargetComponent" then
            say(string.format("-- %s: from %s -- SKIPPED (known crash walking this component's own properties)", tag, className))
        else
            say(string.format("-- %s: from %s --", tag, className))
            pcall(function()
                cls:ForEachProperty(function(prop)
                    local pname = "?"
                    pcall(function() pname = prop:GetFName():ToString() end)
                    local valStr = "<unreadable>"
                    local okv, val = pcall(function() return obj[pname] end)
                    if okv then
                        if val == nil then valStr = "nil"
                        elseif type(val) == "userdata" then
                            local okc, full = pcall(function() return val:GetFullName() end)
                            valStr = okc and full or tostring(val)
                        else valStr = tostring(val) end
                    end
                    say(string.format("  %s = %s", pname, valStr))
                end)
            end)
        end
        local nextCls
        pcall(function() nextCls = cls:GetSuperStruct() end)
        cls = nextCls
    end
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rftarget", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rftarget] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local p1 = (Parameters and Parameters[1] or ""):lower()
            if p1 == "player" or p1 == "self" then
                local pc = UEHelpers.GetPlayerController()
                local pawn = pc and pc:IsValid() and pc.Pawn
                if not (pawn and pawn:IsValid()) then say("could not resolve your own pawn."); return true end
                RF.lastProbed = pawn
                say("targeted: your own pawn. Run rftargetdata or rfgettargetfuncs now.")
            elseif p1 == "child" then
                local propName = Parameters and Parameters[2]
                if not (propName and propName ~= "") then
                    say("usage: rftarget child <propertyName> -- re-points the target at a named actor-reference property on whatever is currently targeted (e.g. if rftargetdata showed a property like 'InteractTargetComponent', run 'rftarget child InteractTargetComponent' to target THAT object instead).")
                    return true
                end
                local cur = RF.lastProbed
                if not (cur and cur:IsValid()) then say("nothing targeted yet -- run rftarget first."); return true end
                local child
                pcall(function() child = cur[propName] end)
                if not (child and child:IsValid()) then
                    say("'" .. propName .. "' is not a valid object reference on the current target.")
                    return true
                end
                RF.lastProbed = child
                local shortName = "?"
                pcall(function() shortName = child:GetClass():GetFName():ToString() end)
                say("targeted (via '" .. propName .. "'): " .. shortName)
            else
                local actor, dist = findNearestActorInFront(400.0)
                if not actor then
                    say("nothing within 400uu of where you're looking -- walk closer and look directly at it.")
                    return true
                end
                RF.lastProbed = actor
                local cls = "?"
                pcall(function() cls = actor:GetClass():GetFullName() end)
                say(string.format("targeted (%.0fuu away): %s", dist or 0, cls))
            end
            return true
        end)
    end)
    registerCmdInfo("rftarget", "rftarget  |  rftarget player  |  rftarget child <propertyName>",
        "Aims using your camera's look direction and remembers the nearest actor in front of you (within 400 units) as the 'current target' for rftargetdata/rfgettargetfuncs/rfnoai. 'rftarget player' targets your own character instead. 'rftarget child <propertyName>' re-points the target at a named object-reference property found on whatever is currently targeted, so you can drill one step deeper (e.g. from an actor into one of its components) -- run rftargetdata first to see what property names are available to drill into.")

    RegisterConsoleCommandHandler("rftargetdata", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rftargetdata] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local target = RF.lastProbed
        if not (target and target:IsValid()) then
            say("nothing targeted -- run rftarget (or rftarget player / rftarget child <name>) first.")
            return true
        end
        dumpObjectProperties(target, "TARGET", say)
        say("done -- this prints to the console and to WindroseConsoleTools.log.")
        return true
    end)
    registerCmdInfo("rftargetdata", "rftargetdata",
        "Prints every property (name and current value) declared on your current target (set by rftarget), walking up its entire class hierarchy from the most specific class to the base Object class. This is how you find out what an object actually is -- its stats, its component references, its settings. Run rftarget first to set a target.")

    RegisterConsoleCommandHandler("rfgettargetfuncs", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfgettargetfuncs] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local target = RF.lastProbed
        if not (target and target:IsValid()) then
            say("nothing targeted -- run rftarget first.")
            return true
        end
        local cls
        pcall(function() cls = target:GetClass() end)
        local total = 0
        while cls and cls:IsValid() do
            local className = "?"
            pcall(function() className = cls:GetFName():ToString() end)
            local names = {}
            pcall(function()
                cls:ForEachFunction(function(fn)
                    local fname = "?"
                    pcall(function() fname = fn:GetFName():ToString() end)
                    names[#names + 1] = fname
                end)
            end)
            table.sort(names)
            total = total + #names
            say(string.format("-- %s (%d function(s)) --", className, #names))
            if #names > 0 then say("  " .. table.concat(names, ", ")) end
            local nextCls
            pcall(function() nextCls = cls:GetSuperStruct() end)
            cls = nextCls
        end
        say(string.format("%d function(s) total. This only lists NAMES (it never calls anything, so it's always safe to run) -- some of these may be internal/engine functions rather than ones you can usefully call from a console command.", total))
        return true
    end)
    registerCmdInfo("rfgettargetfuncs", "rfgettargetfuncs",
        "Lists the name of every function declared on your current target's class (and every parent class above it), without calling any of them -- purely a read-only listing. Useful when rftargetdata shows an object with few or no readable properties, since some game objects expose their real data only through getter functions instead of plain properties.")
end

----------------------------------------------------------------------------------------------
-- rfentityspawn / rfdespawn -- spawn a class by its full path, and clean it back up again. Only
-- ever acts on actors THIS mod spawned (tracked in RF.spawned) -- it will never destroy something
-- that was already in the world.
----------------------------------------------------------------------------------------------

local beginVariants = {
    { name = "UE5.6 (6 args)", call = function(gs, w, c, t) return gs:BeginDeferredActorSpawnFromClass(w, c, t, 1, nil, 1) end },
    { name = "UE5.6 (7 args)", call = function(gs, w, c, t) return gs:BeginDeferredActorSpawnFromClass(w, c, t, 1, nil, 1, nil) end },
    { name = "UE4 classic (5 args)", call = function(gs, w, c, t) return gs:BeginDeferredActorSpawnFromClass(w, c, t, 1, nil) end },
}
local finishVariants = {
    { name = "UE5 (3 args)", call = function(gs, a, t) return gs:FinishSpawningActor(a, t, 1) end },
    { name = "UE4 classic (2 args)", call = function(gs, a, t) return gs:FinishSpawningActor(a, t) end },
    { name = "UE5 (4 args)", call = function(gs, a, t) return gs:FinishSpawningActor(a, t, 1, nil) end },
}
local lockedBegin, lockedFinish = nil, nil

-- Spawns one instance of classPath at the given transform. Tries each known
-- BeginDeferredActorSpawnFromClass/FinishSpawningActor call signature in turn (different UE5
-- versions expose different argument counts) and remembers whichever one worked for next time.
local function engineSpawn(gs, world, cls, transform, say)
    local deferred
    if lockedBegin then
        local ok, res = pcall(lockedBegin.call, gs, world, cls, transform)
        if ok then deferred = res else lockedBegin = nil end
    end
    if not deferred then
        for _, v in ipairs(beginVariants) do
            local ok, res = pcall(v.call, gs, world, cls, transform)
            if ok and res and res:IsValid() then deferred = res; lockedBegin = v; break end
        end
    end
    if not (deferred and deferred:IsValid()) then
        say("spawn failed -- the class path may be wrong, or not an Actor-derived class.")
        return nil
    end
    local finished = false
    if lockedFinish then
        local ok = pcall(lockedFinish.call, gs, deferred, transform)
        if ok then finished = true else lockedFinish = nil end
    end
    if not finished then
        for _, v in ipairs(finishVariants) do
            local ok = pcall(v.call, gs, deferred, transform)
            if ok then finished = true; lockedFinish = v; break end
        end
    end
    if not finished then
        say("spawn failed while finishing (the actor was created but never finalized).")
        pcall(function() deferred:K2_DestroyActor() end)
        return nil
    end
    return deferred
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfentityspawn", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfentityspawn] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local classPath = Parameters and Parameters[1]
            if not (classPath and classPath ~= "") then
                say("usage: rfentityspawn </Game/Path/To/BP_Something.BP_Something_C> [yaw] -- spawns one instance of the given class a short distance in front of you, facing the given yaw in degrees (default 0). The class path must be the FULL path including the trailing _C, exactly as UE4SS's own class/object dump tools report it.")
                return true
            end
            local yaw = tonumber(Parameters and Parameters[2]) or 0.0
            local gs = getGameplayStatics()
            local world = UEHelpers.GetWorld()
            local pc = UEHelpers.GetPlayerController()
            local pawn = pc and pc:IsValid() and pc.Pawn
            if not (gs and world and world:IsValid() and pawn and pawn:IsValid()) then
                say("could not resolve GameplayStatics/World/PlayerPawn -- are you fully loaded into a world?")
                return true
            end
            local cls
            pcall(function() cls = StaticFindObject(classPath) end)
            if not (cls and cls:IsValid()) then
                say("could not resolve class: " .. classPath .. " -- check the spelling/path (it must include the trailing _C).")
                return true
            end
            local loc = pawn:K2_GetActorLocation()
            local fwdYaw = math.rad(yaw)
            local spawnLoc = { X = loc.X + 200.0 * math.cos(fwdYaw), Y = loc.Y + 200.0 * math.sin(fwdYaw), Z = loc.Z }
            local transform = {
                Rotation = { W = math.cos(math.rad(yaw) / 2), X = 0.0, Y = 0.0, Z = math.sin(math.rad(yaw) / 2) },
                Translation = spawnLoc, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 },
            }
            local actor = engineSpawn(gs, world, cls, transform, say)
            if not actor then return true end
            RF.spawned[#RF.spawned + 1] = { actor = actor, classPath = classPath }
            RF.lastProbed = actor
            say(string.format("spawned %s (now %d tracked spawn(s) -- rfdespawn removes the nearest one in front of you).", classPath, #RF.spawned))
            return true
        end)
    end)
    registerCmdInfo("rfentityspawn", "rfentityspawn </Game/Path/To/BP_Something.BP_Something_C> [yaw]",
        "Spawns one instance of the given class about 200 units in front of you, optionally facing the given yaw in degrees (default 0 = facing the same direction you are). The class path must be the full /Game/... path including the trailing _C. This is for quick testing/visual checks only -- nothing spawned this way is saved: it exists only for the current play session (closing the game, or running rfdespawn, removes it). Not every class is spawnable this way -- some require extra setup the engine can't provide generically and will fail with a 'spawn failed' message.")

    RegisterConsoleCommandHandler("rfdespawn", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfdespawn] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        -- Clean up any stale entries (actor already gone for some other reason) before searching.
        for i = #RF.spawned, 1, -1 do
            local e = RF.spawned[i]
            if not (e.actor and e.actor:IsValid()) then table.remove(RF.spawned, i) end
        end
        if #RF.spawned == 0 then
            say("nothing tracked -- this command only removes actors spawned by rfentityspawn, and none are currently tracked.")
            return true
        end
        local pc = UEHelpers.GetPlayerController()
        local pawn = pc and pc:IsValid() and pc.Pawn
        if not (pawn and pawn:IsValid()) then say("could not resolve your own pawn."); return true end
        local loc = pawn:K2_GetActorLocation()
        local bestI, bestDist
        for i, e in ipairs(RF.spawned) do
            local ok, aloc = pcall(function() return e.actor:K2_GetActorLocation() end)
            if ok and aloc then
                local dx, dy, dz = aloc.X - loc.X, aloc.Y - loc.Y, aloc.Z - loc.Z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if not bestDist or dist < bestDist then bestI, bestDist = i, dist end
            end
        end
        if not bestI then say("could not find any valid tracked spawn."); return true end
        local entry = RF.spawned[bestI]
        pcall(function() entry.actor:K2_DestroyActor() end)
        table.remove(RF.spawned, bestI)
        say(string.format("despawned the nearest tracked spawn (%.0f units away): %s. %d tracked spawn(s) remain.", bestDist or 0, entry.classPath, #RF.spawned))
        return true
    end)
    registerCmdInfo("rfdespawn", "rfdespawn",
        "Removes the NEAREST actor that YOU previously spawned with rfentityspawn (distance measured from your own character, regardless of which way you're facing). Only ever affects actors this mod itself spawned and is still tracking -- it will never remove anything that already existed in the world. If you've spawned several things, run it repeatedly, nearest first.")
end

----------------------------------------------------------------------------------------------
-- rfnoai -- freeze/resume AI on the current target (set by rftarget)
----------------------------------------------------------------------------------------------

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfnoai", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfnoai] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local modeArg = (Parameters and Parameters[1] or "on"):lower()
            local wantFreeze = not (modeArg == "off" or modeArg == "resume" or modeArg == "unfreeze")
            local target = RF.lastProbed
            if not (target and target:IsValid()) then
                say("nothing targeted -- run rftarget on an NPC/creature first.")
                return true
            end
            local ctrl
            pcall(function() ctrl = target.Controller end)
            if not (ctrl and ctrl:IsValid()) then pcall(function() ctrl = target:GetR5AIController() end) end
            if not (ctrl and ctrl:IsValid()) then
                say("current target has no AI controller -- it's probably not an NPC/creature.")
                return true
            end
            local okLogic = pcall(function()
                if wantFreeze then ctrl:StopLogic() else ctrl:StartLogic() end
            end)
            -- StopLogic alone can leave a still-moving actor (e.g. mid-charge) sliding for a bit --
            -- also zeroing its current movement directly makes freeze actually instant.
            if wantFreeze then
                pcall(function()
                    local move = target.CharacterMovement
                    if move and move:IsValid() then
                        move.MaxWalkSpeed = 0.0
                        move:StopMovementImmediately()
                    end
                end)
            end
            say(string.format("%s AI on current target: %s", wantFreeze and "froze" or "resumed", tostring(okLogic)))
            return true
        end)
    end)
    registerCmdInfo("rfnoai", "rfnoai [on|off]",
        "Freezes (default, or 'on') or resumes ('off') the AI of your current target (set by rftarget) -- it stops moving/acting, which is useful for inspecting an NPC or creature up close without it wandering off or attacking. This stops its AI 'brain' and zeroes its current movement; it does not make it invulnerable or otherwise change its stats.")
end

----------------------------------------------------------------------------------------------
-- rfnoclip -- direct-property no-clip toggle for your own character
----------------------------------------------------------------------------------------------

local RFNOCLIP = { active = false }

-- While noclip is active, redirects your EXISTING horizontal velocity (which the game's own
-- input still only computes along flat yaw -- that never changed) into the camera's real,
-- full-pitch look direction every tick, so looking up/down and moving forward actually climbs/
-- descends like a normal free-fly camera, with no held key needed. Works by decomposing the
-- current velocity into forward/right amounts using the PAWN's flat yaw basis (which is how it
-- was built), then reconstructing a new velocity of the same two amounts along the CAMERA's
-- pitched forward (strafe stays flat -- tilting strafe too felt wrong in practice for every
-- free-fly camera this kind of trick has been tried on, so it isn't done here). No native input
-- hook needed -- this never touches input, only the velocity the engine already produced.
local function rfnoclipDirectionTick()
    ExecuteWithDelay(100, function()
        if RFNOCLIP.active then
            ExecuteInGameThread(function()
                pcall(function()
                    local pc = UEHelpers.GetPlayerController()
                    local pawn = pc and pc:IsValid() and pc.Pawn
                    if not (pc and pc:IsValid() and pawn and pawn:IsValid()) then return end
                    local move = pawn.CharacterMovement
                    if not (move and move:IsValid()) then return end
                    local vel = move.Velocity
                    if not vel then return end
                    local pawnRot = pawn:K2_GetActorRotation()
                    local camRot = pc:GetControlRotation()
                    if not (pawnRot and camRot) then return end
                    local yawRad = math.rad(pawnRot.Yaw)
                    local fwdFlatX, fwdFlatY = math.cos(yawRad), math.sin(yawRad)
                    local rightFlatX, rightFlatY = -math.sin(yawRad), math.cos(yawRad)
                    local forwardAmount = vel.X * fwdFlatX + vel.Y * fwdFlatY
                    local rightAmount = vel.X * rightFlatX + vel.Y * rightFlatY
                    if math.abs(forwardAmount) < 1.0 and math.abs(rightAmount) < 1.0 then return end -- not moving, leave it alone
                    local camYawRad, camPitchRad = math.rad(camRot.Yaw), math.rad(camRot.Pitch)
                    local cp = math.cos(camPitchRad)
                    local fwd3X, fwd3Y, fwd3Z = math.cos(camYawRad) * cp, math.sin(camYawRad) * cp, math.sin(camPitchRad)
                    local right3X, right3Y = -math.sin(camYawRad), math.cos(camYawRad)
                    local newVel = {
                        X = fwd3X * forwardAmount + right3X * rightAmount,
                        Y = fwd3Y * forwardAmount + right3Y * rightAmount,
                        Z = fwd3Z * forwardAmount,
                    }
                    move.Velocity = newVel
                end)
            end)
        end
        rfnoclipDirectionTick()
    end)
end
if ExecuteWithDelay then rfnoclipDirectionTick() end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfnoclip", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfnoclip] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local mode = (Parameters and Parameters[1] or "on"):lower()
            if mode ~= "on" and mode ~= "off" then
                say("usage: rfnoclip <on|off>")
                return true
            end
            local pc = UEHelpers.GetPlayerController()
            local pawn = pc and pc:IsValid() and pc.Pawn
            if not (pawn and pawn:IsValid()) then say("no player pawn found."); return true end
            local move = pawn.CharacterMovement
            if not (move and move:IsValid()) then say("pawn.CharacterMovement not found/readable."); return true end
            -- SetActorEnableCollision(false) (an earlier attempt) was confirmed live to break
            -- movement entirely and send Jump's velocity up forever -- CharacterMovementComponent
            -- needs its OWN capsule collision to stay ENABLED for its normal sweep/floor-detection
            -- pipeline to run at all. Fix: leave CollisionEnabled alone, just set the RESPONSE to
            -- every channel to Ignore (0) on the capsule/root, so nothing physically blocks the
            -- pawn but the movement component's internals keep working normally.
            local root
            pcall(function() root = pawn:K2_GetRootComponent() end)
            if mode == "on" then
                -- Direct property writes, not the SetMovementMode()/etc UFUNCTIONs -- this
                -- game's own cheat UFUNCTIONs are confirmed unreliable in this build, and a
                -- :SetMovementMode(5) call was confirmed live to not actually stick (symptom:
                -- stuck in a falling animation, sliding like on ice). BrakingDecelerationFlying
                -- also matters: Flying mode's default is near zero, which is the OTHER half of
                -- that same "sliding, no deliberate up/down control" symptom.
                pcall(function() move.GravityScale = 0.0 end)
                pcall(function() move.MovementMode = 5 end) -- 5 = Flying
                pcall(function() move.BrakingDecelerationFlying = 2048.0 end)
                if root and root:IsValid() then pcall(function() root:SetCollisionResponseToAllChannels(0) end) end -- Ignore
                RFNOCLIP.active = true
            else
                RFNOCLIP.active = false
                if root and root:IsValid() then pcall(function() root:SetCollisionResponseToAllChannels(2) end) end -- Block
                pcall(function() move.GravityScale = 1.0 end)
                pcall(function() move.MovementMode = 1 end) -- 1 = Walking
            end
            local gAfter, mAfter
            pcall(function() gAfter = move.GravityScale end)
            pcall(function() mAfter = move.MovementMode end)
            say(string.format("%s -- readback: GravityScale=%s MovementMode=%s", mode, tostring(gAfter), tostring(mAfter)))
            return true
        end)
    end)
    registerCmdInfo("rfnoclip", "rfnoclip <on|off>",
        "Toggles no-clip (fly freely through walls/terrain, no gravity) on your own character, by writing directly to its movement component (the game's built-in Ghost()/Fly() cheat functions are confirmed non-functional in this build, which is why this writes the underlying properties directly instead). While active, looking up/down and moving forward actually climbs/descends like a normal free-fly camera -- your existing movement keys work, you don't need a separate up/down key. Prints a readback of the values it just set, so you can confirm it actually took effect. rfnudge is still available as a precise alternative if you want exact vertical control.")
end

----------------------------------------------------------------------------------------------
-- rfmeshspawn / rfmeshsolid -- raw static-mesh decor preview, and a collision toggle for it
----------------------------------------------------------------------------------------------

local function resolveAsset(path)
    local obj = StaticFindObject(path)
    if obj and obj:IsValid() then return obj end
    local okLoad = pcall(function() LoadAsset(path) end)
    if okLoad then
        obj = StaticFindObject(path)
        if obj and obj:IsValid() then return obj end
    end
    return nil
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfmeshspawn", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfmeshspawn] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local meshPath = Parameters and Parameters[1]
            if not (meshPath and meshPath ~= "") then
                say("usage: rfmeshspawn </Game/Path/To/SM_Something.SM_Something> [zOffset] -- spawns the given static mesh as plain inert decor (no pickup behavior) 200 units in front of you, raised by zOffset units (default 20). The path must include the trailing '.AssetName' suffix, e.g. '...SM_Foo.SM_Foo'.")
                return true
            end
            local z = tonumber(Parameters and Parameters[2]) or 20.0
            local gs = getGameplayStatics()
            local world = UEHelpers.GetWorld()
            local pc = UEHelpers.GetPlayerController()
            local pawn = pc and pc:IsValid() and pc.Pawn
            if not (gs and world and world:IsValid() and pawn and pawn:IsValid()) then
                say("could not resolve GameplayStatics/World/PlayerPawn -- are you fully loaded into a world?")
                return true
            end
            local wrapperCls
            pcall(function() wrapperCls = StaticFindObject("/Script/R5.R5LootActor") end)
            if not (wrapperCls and wrapperCls:IsValid()) then
                say("could not resolve the native R5LootActor wrapper class.")
                return true
            end
            local loc = pawn:K2_GetActorLocation()
            local rot = pawn:K2_GetActorRotation()
            local fwdYaw = math.rad(rot.Yaw)
            local spawnLoc = { X = loc.X + 200.0 * math.cos(fwdYaw), Y = loc.Y + 200.0 * math.sin(fwdYaw), Z = loc.Z + z }
            local transform = {
                Rotation = { W = 1.0, X = 0.0, Y = 0.0, Z = 0.0 },
                Translation = spawnLoc, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 },
            }
            local actor = engineSpawn(gs, world, wrapperCls, transform, say)
            if not actor then return true end
            local mesh = resolveAsset(meshPath)
            if not (mesh and mesh:IsValid()) then
                say("spawned the wrapper, but could not resolve mesh: " .. meshPath .. " -- check the path/suffix. Destroying the empty wrapper.")
                pcall(function() actor:K2_DestroyActor() end)
                return true
            end
            local mc
            pcall(function() mc = actor.MeshComponent end)
            if not (mc and mc:IsValid()) then say("spawned wrapper has no MeshComponent -- aborting."); pcall(function() actor:K2_DestroyActor() end); return true end
            local okMesh = pcall(function() mc:SetStaticMesh(mesh) end)
            if not okMesh then say("SetStaticMesh failed."); pcall(function() actor:K2_DestroyActor() end); return true end
            -- Strip the pickup/toss behavior so it just sits there as decor: destroy the
            -- interaction-prompt and projectile-movement components, and stop the pickup sparkle.
            pcall(function()
                local interactCls1 = StaticFindObject("/Script/R5.R5CommonInteractionTargetComponent")
                local interactCls2 = StaticFindObject("/Script/R5.R5PrimitiveInteractionTargetComponent")
                for _, cls in ipairs({ interactCls1, interactCls2 }) do
                    if cls and cls:IsValid() then
                        local comps = actor:K2_GetComponentsByClass(cls)
                        local n = 0
                        pcall(function() n = comps:GetArrayNum() end)
                        if n == 0 then pcall(function() n = #comps end) end
                        for i = 1, n do
                            local raw = comps[i]
                            if raw then
                                local c = raw
                                pcall(function() local u = raw:get(); if u then c = u end end)
                                if c and c:IsValid() then pcall(function() c:K2_DestroyComponent(actor) end) end
                            end
                        end
                    end
                end
            end)
            pcall(function()
                local moveCls = StaticFindObject("/Script/R5.R5LootMovementComponent")
                if moveCls and moveCls:IsValid() then
                    local comps = actor:K2_GetComponentsByClass(moveCls)
                    local n = 0
                    pcall(function() n = comps:GetArrayNum() end)
                    if n == 0 then pcall(function() n = #comps end) end
                    for i = 1, n do
                        local raw = comps[i]
                        if raw then
                            local c = raw
                            pcall(function() local u = raw:get(); if u then c = u end end)
                            if c and c:IsValid() then pcall(function() c:K2_DestroyComponent(actor) end) end
                        end
                    end
                end
            end)
            pcall(function()
                local niag = actor.NiagaraComponent
                if niag and niag:IsValid() then niag:Deactivate() end
            end)
            RF.spawned[#RF.spawned + 1] = { actor = actor, classPath = meshPath }
            RF.lastProbed = actor
            say(string.format("spawned decor mesh %s (zOffset=%.1f) -- rfdespawn removes it, rfmeshsolid can make it a real physical blocker.", meshPath, z))
            return true
        end)
    end)
    registerCmdInfo("rfmeshspawn", "rfmeshspawn </Game/Path/To/SM_Something.SM_Something> [zOffset]",
        "Spawns a raw static mesh asset as plain inert decoration (no pickup glow, no physics toss) 200 units in front of you, raised by zOffset units (default 20). Useful for previewing an asset without needing to add it to any kind of item list first. The path must be the full /Game/... path and must repeat the asset name after the final dot, e.g. '/Game/.../SM_Foo.SM_Foo'. Tracked the same way as rfentityspawn -- rfdespawn removes it.")

    RegisterConsoleCommandHandler("rfmeshsolid", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfmeshsolid] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local mode = (Parameters and Parameters[1] or "on"):lower()
        if mode ~= "on" and mode ~= "off" then say("usage: rfmeshsolid <on|off>"); return true end
        local target = RF.lastProbed
        if not (target and target:IsValid()) then say("nothing targeted -- run rftarget on a decor mesh first."); return true end
        local mc
        pcall(function() mc = target.MeshComponent end)
        if not (mc and mc:IsValid()) then pcall(function() mc = target.StaticMeshComponent end) end
        if not (mc and mc:IsValid()) then say("current target has no MeshComponent/StaticMeshComponent -- this only works on raw static-mesh decor."); return true end
        local root
        pcall(function() root = target:K2_GetRootComponent() end)
        pcall(function() target:SetActorEnableCollision(mode == "on") end)
        for _, c in ipairs({ mc, root }) do
            if c and c:IsValid() then
                if mode == "on" then
                    pcall(function() c:SetCollisionEnabled(3) end)             -- QueryAndPhysics
                    pcall(function() c:SetCollisionResponseToAllChannels(2) end) -- Block
                else
                    pcall(function() c:SetCollisionEnabled(0) end)             -- NoCollision
                end
            end
        end
        say(string.format("collision on current target set to %s.", mode))
        return true
    end)
    registerCmdInfo("rfmeshsolid", "rfmeshsolid <on|off>",
        "Makes your current target (set by rftarget) a real physical blocker you can't walk through ('on'), or removes its collision entirely ('off'). Most raw decor meshes default to pass-through/overlap-only collision (you can walk right through them) -- this is how you make one actually solid, or undo that.")
end

----------------------------------------------------------------------------------------------
-- rfcamera / rfcammove / rfcamrotate / rfcamfov / rfcamcoords -- a repositionable photo camera.
-- Tripod faces the same way you were facing when activated; Selfie faces back at you and keeps
-- tracking your look direction every frame. Both are a single plain CameraActor, not a cooked
-- Blueprint asset -- no extra pak/content dependency.
----------------------------------------------------------------------------------------------

local RFCAM = { state = "OFF", tripodBase = nil }

local function rfcamComputeEyePose()
    local pc = UEHelpers.GetPlayerController()
    local pawn = pc and pc:IsValid() and pc.Pawn
    if not (pc and pc:IsValid() and pawn and pawn:IsValid()) then return nil end
    local pos
    pcall(function()
        local mesh = pawn.Mesh
        if mesh and mesh:IsValid() then
            local headLoc = mesh:GetSocketLocation(FName("head"))
            if headLoc then pos = { X = headLoc.X, Y = headLoc.Y, Z = headLoc.Z + 5.0 } end
        end
    end)
    if not pos then
        local okLoc, loc = pcall(function() return pawn:K2_GetActorLocation() end)
        if okLoc and loc then pos = { X = loc.X, Y = loc.Y, Z = loc.Z + 160.0 } end
    end
    local rot
    pcall(function() rot = pc:GetControlRotation() end)
    if not (pos and rot) then return nil end
    return { pos = pos, rot = { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = 0.0 } }
end

local function rfcamComputeSelfiePose()
    local pc = UEHelpers.GetPlayerController()
    local pawn = pc and pc:IsValid() and pc.Pawn
    if not (pc and pc:IsValid() and pawn and pawn:IsValid()) then return nil end
    local rot
    pcall(function() rot = pc:GetControlRotation() end)
    if not rot then return nil end
    local headPos
    pcall(function()
        local mesh = pawn.Mesh
        if mesh and mesh:IsValid() then
            local loc = mesh:GetSocketLocation(FName("head"))
            if loc then headPos = { X = loc.X, Y = loc.Y, Z = loc.Z } end
        end
    end)
    if not headPos then
        local okLoc, loc = pcall(function() return pawn:K2_GetActorLocation() end)
        if okLoc and loc then headPos = { X = loc.X, Y = loc.Y, Z = loc.Z + 160.0 } end
    end
    if not headPos then return nil end
    local yawRad, pitchRad = math.rad(rot.Yaw), math.rad(rot.Pitch)
    local fwdX = math.cos(yawRad) * math.cos(pitchRad)
    local fwdY = math.sin(yawRad) * math.cos(pitchRad)
    local fwdZ = math.sin(pitchRad)
    local dist = 110.0
    local pos = { X = headPos.X + fwdX * dist, Y = headPos.Y + fwdY * dist, Z = headPos.Z + fwdZ * dist }
    local camRot = { Pitch = -rot.Pitch, Yaw = rot.Yaw + 180.0, Roll = 0.0 }
    return { pos = pos, rot = camRot }
end

local function rfcamResolveActor()
    if RFCAM.actor and RFCAM.actor:IsValid() then return RFCAM.actor end
    return nil
end

local function rfcamSpawnIfNeeded(say)
    if rfcamResolveActor() then return RFCAM.actor end
    local cls
    pcall(function() cls = StaticFindObject("/Script/Engine.CameraActor") end)
    if not (cls and cls:IsValid()) then say("could not resolve CameraActor class."); return nil end
    local gs = getGameplayStatics()
    local world = UEHelpers.GetWorld()
    if not (gs and world and world:IsValid()) then say("no GameplayStatics/World available."); return nil end
    local transform = { Rotation = { W = 1.0, X = 0.0, Y = 0.0, Z = 0.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
    local cam = engineSpawn(gs, world, cls, transform, say)
    if not (cam and cam:IsValid()) then say("camera actor spawn failed."); return nil end
    RFCAM.actor = cam
    return cam
end

local function rfcamApplyPose(pose, say)
    if not (pose and pose.pos and pose.rot) then say("no pose to apply."); return false end
    local cam = rfcamSpawnIfNeeded(say)
    if not cam then return false end
    local pc = UEHelpers.GetPlayerController()
    if pc and pc:IsValid() then pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end) end
    local okPos = pcall(function() cam:K2_SetActorLocation(pose.pos, false, {}, false) end)
    local okRot = pcall(function() cam:K2_SetActorRotation(pose.rot, false) end)
    return okPos and okRot
end

local function rfcamOff(say)
    local pc = UEHelpers.GetPlayerController()
    local pawn = pc and pc:IsValid() and pc.Pawn
    if pc and pc:IsValid() and pawn and pawn:IsValid() then
        pcall(function() pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end)
    end
    if RFCAM.actor and RFCAM.actor:IsValid() then pcall(function() RFCAM.actor:K2_DestroyActor() end) end
    RFCAM.actor = nil
    RFCAM.state = "OFF"
    RFCAM.tripodBase = nil
end

-- Keeps Selfie tracking your live look direction every frame while active -- this is the one part
-- of the camera system that needs an always-on tick (Tripod is a static snapshot and needs none).
local function rfcamSelfieTick()
    ExecuteWithDelay(100, function()
        if RFCAM.state == "SELFIE" then
            local pose = rfcamComputeSelfiePose()
            if pose then pcall(function() rfcamApplyPose(pose, function() end) end) end
        end
        rfcamSelfieTick()
    end)
end
if ExecuteWithDelay then rfcamSelfieTick() end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfcamera", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfcamera] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local mode = (Parameters and Parameters[1] or ""):lower()
            if mode == "off" then
                rfcamOff(say)
                say("camera off -- view restored to your own character.")
                return true
            elseif mode == "reset" then
                if RFCAM.state == "TRIPOD" then
                    local base = rfcamComputeEyePose()
                    if not base then say("could not read your pose."); return true end
                    RFCAM.tripodBase = base
                    rfcamApplyPose(base, say)
                    say("tripod re-anchored to your current position/facing.")
                elseif RFCAM.state == "SELFIE" then
                    say("selfie has no reset -- it already follows your current look direction every frame.")
                else
                    say("no active camera to reset -- run rfcamera tripod or rfcamera selfie first.")
                end
                return true
            elseif mode == "tripod" then
                local base = RFCAM.tripodBase or rfcamComputeEyePose()
                if not base then say("could not read your pose."); return true end
                RFCAM.tripodBase = base
                RFCAM.state = "TRIPOD"
                rfcamApplyPose(base, say)
                say("tripod camera active -- facing the same direction you were. rfcammove/rfcamrotate/rfcamfov/rfcamcoords all act on it now.")
                return true
            elseif mode == "selfie" then
                local base = rfcamComputeSelfiePose()
                if not base then say("could not read your pose."); return true end
                RFCAM.state = "SELFIE"
                rfcamApplyPose(base, say)
                say("selfie camera active -- facing back at you, tracking your look direction. rfcammove/rfcamrotate/rfcamfov/rfcamcoords still work, but selfie keeps re-aiming itself at your face every frame on top of them.")
                return true
            else
                say("usage: rfcamera <tripod|selfie|off|reset>")
                return true
            end
        end)
    end)
    registerCmdInfo("rfcamera", "rfcamera <tripod|selfie|off|reset>",
        "Spawns (or repositions) a standalone camera for taking screenshots. 'tripod' places it where you're standing, facing the same direction you are, and leaves it there even as you walk away -- good for a fixed-composition shot. 'selfie' places it in front of your face, facing back at you, and keeps following your look direction every frame -- good for a selfie-style shot. 'off' removes the camera and returns your view to normal. 'reset' re-anchors tripod mode to your current position (selfie has nothing to reset, since it always follows you). Only one camera is active at a time -- switching modes replaces whichever one was active. This is a plain engine camera, not a custom asset, so it works with just this mod installed.")

    RegisterConsoleCommandHandler("rfcammove", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfcammove] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local cam = rfcamResolveActor()
        if not cam then say("no active camera -- run rfcamera tripod or rfcamera selfie first."); return true end
        local axis = (Parameters and Parameters[1] or ""):lower()
        local amount = tonumber(Parameters and Parameters[2])
        if not (amount and (axis == "x" or axis == "y" or axis == "z")) then
            say("usage: rfcammove <x|y|z> <amount>")
            return true
        end
        local loc = cam:K2_GetActorLocation()
        local newLoc = { X = loc.X, Y = loc.Y, Z = loc.Z }
        newLoc[axis:upper()] = loc[axis:upper()] + amount
        local ok = pcall(function() cam:K2_SetActorLocation(newLoc, false, {}, false) end)
        say(string.format("moved %s by %.2f -- now at (%.1f, %.1f, %.1f): %s", axis, amount, newLoc.X, newLoc.Y, newLoc.Z, tostring(ok)))
        return true
    end)
    registerCmdInfo("rfcammove", "rfcammove <x|y|z> <amount>",
        "Nudges the active rfcamera camera along one world axis by a signed amount (positive or negative), for exact/repeatable positioning. Does nothing (with a message) if no camera is currently active.")

    RegisterConsoleCommandHandler("rfcamrotate", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfcamrotate] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local cam = rfcamResolveActor()
        if not cam then say("no active camera -- run rfcamera tripod or rfcamera selfie first."); return true end
        local axis = (Parameters and Parameters[1] or ""):lower()
        local amount = tonumber(Parameters and Parameters[2])
        local key = ({ pitch = "Pitch", yaw = "Yaw", roll = "Roll" })[axis]
        if not (amount and key) then
            say("usage: rfcamrotate <pitch|yaw|roll> <amount>")
            return true
        end
        local rot = cam:K2_GetActorRotation()
        local newRot = { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }
        newRot[key] = rot[key] + amount
        local ok = pcall(function() cam:K2_SetActorRotation(newRot, false) end)
        say(string.format("rotated %s by %.2f -- now Pitch=%.1f Yaw=%.1f Roll=%.1f: %s", axis, amount, newRot.Pitch, newRot.Yaw, newRot.Roll, tostring(ok)))
        return true
    end)
    registerCmdInfo("rfcamrotate", "rfcamrotate <pitch|yaw|roll> <amount>",
        "Rotates the active rfcamera camera on one axis by a signed number of degrees, for exact/repeatable framing. Does nothing (with a message) if no camera is currently active.")

    RegisterConsoleCommandHandler("rfcamfov", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfcamfov] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local cam = rfcamResolveActor()
        if not cam then say("no active camera -- run rfcamera tripod or rfcamera selfie first."); return true end
        local value = tonumber(Parameters and Parameters[1])
        if not value then say("usage: rfcamfov <value> (e.g. 90)"); return true end
        local camComp
        pcall(function() camComp = cam.CameraComponent end)
        if not (camComp and camComp:IsValid()) then say("could not read the camera's CameraComponent."); return true end
        local ok = pcall(function() camComp.FieldOfView = value end)
        say(string.format("FOV set to %.1f: %s", value, tostring(ok)))
        return true
    end)
    registerCmdInfo("rfcamfov", "rfcamfov <value>",
        "Sets the field of view (in degrees, e.g. 90) on the active rfcamera camera's lens. Does nothing (with a message) if no camera is currently active.")

    RegisterConsoleCommandHandler("rfcamcoords", function(FullCommand, Parameters, Ar)
        local function say(msg)
            print("[WindroseConsoleTools] [rfcamcoords] " .. msg .. "\n")
            pcall(function()
                if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
            end)
        end
        local cam = rfcamResolveActor()
        if not cam then say("no active camera -- run rfcamera tripod or rfcamera selfie first."); return true end
        local function parse3(s)
            if not s then return nil end
            local a, b, c = s:match("^%s*(-?[%d.]+)%s*,%s*(-?[%d.]+)%s*,%s*(-?[%d.]+)%s*$")
            if not a then return nil end
            return tonumber(a), tonumber(b), tonumber(c)
        end
        local posStr, rotStr = Parameters and Parameters[1], Parameters and Parameters[2]
        if not posStr and not rotStr then
            local loc, rot = cam:K2_GetActorLocation(), cam:K2_GetActorRotation()
            say(string.format("current pose: %.1f,%.1f,%.1f  %.2f,%.2f,%.2f", loc.X, loc.Y, loc.Z, rot.Pitch, rot.Yaw, rot.Roll))
            say(string.format("reproduce with: rfcamcoords %.1f,%.1f,%.1f %.2f,%.2f,%.2f", loc.X, loc.Y, loc.Z, rot.Pitch, rot.Yaw, rot.Roll))
            return true
        end
        local px, py, pz = parse3(posStr)
        if posStr and not px then say("bad position -- expected X,Y,Z with no spaces (e.g. -808407.4,126372.4,300)"); return true end
        if px then
            local ok = pcall(function() cam:K2_SetActorLocation({ X = px, Y = py, Z = pz }, false, {}, false) end)
            say(string.format("position -> %.1f,%.1f,%.1f : %s", px, py, pz, tostring(ok)))
        end
        local rp, ry, rr = parse3(rotStr)
        if rotStr and not rp then say("bad rotation -- expected Pitch,Yaw,Roll with no spaces (e.g. -10,45,0)"); return true end
        if rp then
            local ok = pcall(function() cam:K2_SetActorRotation({ Pitch = rp, Yaw = ry, Roll = rr }, false) end)
            say(string.format("rotation -> Pitch=%.2f Yaw=%.2f Roll=%.2f : %s", rp, ry, rr, tostring(ok)))
        end
        return true
    end)
    registerCmdInfo("rfcamcoords", "rfcamcoords  |  rfcamcoords <X,Y,Z>  |  rfcamcoords <X,Y,Z> <Pitch,Yaw,Roll>",
        "Reads or sets the active rfcamera camera's exact position and rotation (each as three comma-separated numbers, no spaces). With no arguments, prints the current pose AND a ready-to-paste command that reproduces it -- useful for saving/restoring a specific shot. With one argument, sets position only. With both, sets position and rotation.")
end

----------------------------------------------------------------------------------------------
-- rfsetweather / rfsettime -- IMPORTANT: both of these write to native game components that
-- have been confirmed to CRASH the game if touched synchronously inside a console command's own
-- handler (even wrapped in ExecuteInGameThread). The fix, proven in Living Base Enhanced: the
-- command handler only ever queues a request into a plain variable; a SEPARATE, independently
-- self-rescheduling ExecuteWithDelay loop (started once at mod load, running for the lifetime of
-- the session) is the only thing that ever actually touches the native component. Do not
-- "simplify" this into a direct call from the handler -- that is the exact thing that crashes.
----------------------------------------------------------------------------------------------

local RF_WEATHERS = {
    { name = "Windy", id = 0 }, { name = "TortugaMist", id = 1 }, { name = "TestSunny", id = 2 },
    { name = "TestCloudy", id = 3 }, { name = "Sunny", id = 4 }, { name = "Storm", id = 5 },
    { name = "RainHeavy", id = 6 }, { name = "Rainbow", id = 7 }, { name = "Rain", id = 8 },
    { name = "Overcast", id = 9 }, { name = "Mist", id = 10 }, { name = "LobbySunny", id = 11 },
    { name = "HighPressure", id = 12 }, { name = "Fog", id = 13 }, { name = "Default", id = 14 },
    { name = "Cloudy", id = 15 }, { name = "AshlandsFog", id = 16 },
}
local pendingWeather = nil
if ExecuteWithDelay then
    local function weatherPollLoop()
        ExecuteWithDelay(200, function()
            if pendingWeather ~= nil then
                local weather = pendingWeather
                pendingWeather = nil
                ExecuteInGameThread(function()
                    local count = 0
                    pcall(function()
                        for _, comp in ipairs(FindAllOf("R5N_WeatherComponent") or {}) do
                            local okName, n = pcall(function() return comp:GetFullName() end)
                            if okName and n and not n:find("Default__") then
                                comp.CheatWeatherID = weather.id
                                count = count + 1
                            end
                        end
                    end)
                    print(string.format("[WindroseConsoleTools] [rfsetweather] done -- %d weather component(s) set to %s (ID=%d).\n", count, weather.name, weather.id))
                end)
            end
            weatherPollLoop()
        end)
    end
    weatherPollLoop()
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfsetweather", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfsetweather] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local nameArg = Parameters and Parameters[1]
            local weather = nil
            if not nameArg then
                for _, w in ipairs(RF_WEATHERS) do if w.name == "Sunny" then weather = w end end
            else
                for _, w in ipairs(RF_WEATHERS) do if w.name:lower() == nameArg:lower() then weather = w end end
            end
            if not weather then
                local names = {}
                for _, w in ipairs(RF_WEATHERS) do names[#names + 1] = w.name end
                say("unknown weather '" .. tostring(nameArg) .. "'. Valid names: " .. table.concat(names, ", "))
                return true
            end
            pendingWeather = weather
            say(string.format("setting weather to %s (ID=%d)... (applies within ~0.2s)", weather.name, weather.id))
            return true
        end)
    end)
    registerCmdInfo("rfsetweather", "rfsetweather [name]",
        "Forces the current weather immediately (no argument = Sunny). Valid names: Windy, TortugaMist, TestSunny, TestCloudy, Sunny, Storm, RainHeavy, Rainbow, Rain, Overcast, Mist, LobbySunny, HighPressure, Fog, Default, Cloudy, AshlandsFog. These are the preset's own in-engine names, not necessarily in an order that means anything -- just try the one you want. Safe to re-run any time weather changes mid-session.")
end

local MIDNIGHT_RAW, NOON_RAW = 0.0, 11.0
local RAW_PER_REAL_HOUR = (NOON_RAW - MIDNIGHT_RAW) / 12.0
local function rfRealHourToRawHour(realHour)
    return (MIDNIGHT_RAW + realHour * RAW_PER_REAL_HOUR) % 24
end
local function rfFindTimeComp()
    for _, c in ipairs(FindAllOf("R5N_DayCycleTimeComponent") or {}) do
        local okName, n = pcall(function() return c:GetFullName() end)
        if okName and n and not n:find("Default__") then return c end
    end
    return nil
end
local pendingTime = false
local origTimeSpeed = nil
if ExecuteWithDelay then
    local function timePollLoop()
        ExecuteWithDelay(200, function()
            local okBody = pcall(function()
                if pendingTime ~= false then
                    local req = pendingTime
                    local comp = rfFindTimeComp()
                    if not comp then
                        print("[WindroseConsoleTools] [rfsettime] day-cycle component not found -- aborting.\n")
                        pendingTime = false
                    elseif req.stage == "start" then
                        pcall(function() comp:SetComponentTickEnabled(true) end)
                        local h0 = nil
                        pcall(function() h0 = comp:GetCurrentTimeInHours() end)
                        if h0 == nil then
                            print("[WindroseConsoleTools] [rfsettime] could not read current hour -- aborting.\n")
                            pendingTime = false
                        else
                            origTimeSpeed = origTimeSpeed or comp.DayCycleSpeedInv
                            comp.DayCycleSpeedInv = req.speedInv
                            print(string.format("[WindroseConsoleTools] [rfsettime] current hour~%.2f, heading to real %.2f at speedInv=%.4f...\n", h0, req.realHour, req.speedInv))
                            pendingTime = { stage = "waiting", realHour = req.realHour, rawHour = req.rawHour, speedInv = req.speedInv, ticks = 0 }
                        end
                    elseif req.stage == "waiting" then
                        local h = nil
                        pcall(function() h = comp:GetCurrentTimeInHours() end)
                        local remaining = h and ((req.rawHour - h) % 24) or nil
                        if h ~= nil and (remaining <= 0.05 or remaining >= 23.95) then
                            local ok = pcall(function() comp:SetComponentTickEnabled(false) end)
                            print(string.format("[WindroseConsoleTools] [rfsettime] arrived at real %.2f -- %s.\n", req.realHour, ok and "frozen exactly" or "freeze call failed, time will keep drifting"))
                            pendingTime = false
                        elseif req.ticks >= 1100 then
                            print(string.format("[WindroseConsoleTools] [rfsettime] safety cutoff (~220s) -- still heading to real %.2f, giving up and restoring normal speed.\n", req.realHour))
                            pcall(function() if origTimeSpeed then comp.DayCycleSpeedInv = origTimeSpeed end end)
                            pendingTime = false
                        else
                            pendingTime = { stage = "waiting", realHour = req.realHour, rawHour = req.rawHour, speedInv = req.speedInv, ticks = req.ticks + 1 }
                        end
                    end
                end
            end)
            if not okBody then
                pendingTime = false
                pcall(function()
                    local comp = rfFindTimeComp()
                    if comp then
                        if origTimeSpeed then comp.DayCycleSpeedInv = origTimeSpeed end
                        comp:SetComponentTickEnabled(true)
                    end
                end)
            end
            timePollLoop()
        end)
    end
    timePollLoop()
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfsettime", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfsettime] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local realHour = tonumber(Parameters and Parameters[1]) or 12.0
            if realHour < 0 then realHour = 0 end
            if realHour > 24 then realHour = 24 end
            local speedInv = tonumber(Parameters and Parameters[2]) or 0.0125
            pendingTime = { stage = "start", realHour = realHour, rawHour = rfRealHourToRawHour(realHour), speedInv = speedInv, ticks = 0 }
            say(string.format("setting time to %.2f (real 24h clock, e.g. 14 = 2pm) -- fast-forwarding then freezing exactly there. May take up to ~20 seconds.", realHour))
            return true
        end)
    end)
    registerCmdInfo("rfsettime", "rfsettime [realHour] [speedInv]",
        "Sets the day/night cycle to a specific hour on a real 24-hour clock (e.g. 14 for 2pm) and freezes it there exactly, for consistent lighting across several screenshots. Takes up to about 20 seconds to arrive, since it works by fast-forwarding the clock rather than teleporting it. speedInv (default 0.0125) controls how fast it fast-forwards -- a smaller number is faster. Safe to re-run any number of times, including right after a previous one finished.")
end

----------------------------------------------------------------------------------------------
-- rftargetmove -- nudge your current target's position/rotation/scale by keyword=amount pairs.
-- Every parameter is a DELTA added to whatever the target already has, and any parameter you
-- leave out is simply not touched (no implicit zeroing) -- e.g. "rftargetmove x=5" only moves it
-- 5 units on X, leaving its current Y/Z/rotation/scale exactly as they were.
----------------------------------------------------------------------------------------------

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rftargetmove", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rftargetmove] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local target = RF.lastProbed
            if not (target and target:IsValid()) then
                say("nothing targeted -- run rftarget first.")
                return true
            end
            local deltas = {}
            local any = false
            for _, tok in ipairs(Parameters or {}) do
                local key, val = tostring(tok):match("^(%a+)=(-?[%d.]+)$")
                if key and val then
                    key = key:lower()
                    local num = tonumber(val)
                    if num and (key == "x" or key == "y" or key == "z" or key == "yaw" or key == "pitch" or key == "roll" or key == "scale") then
                        deltas[key] = num
                        any = true
                    else
                        say("ignored unrecognized parameter: " .. tostring(tok))
                    end
                else
                    say("ignored malformed parameter (expected key=amount, e.g. x=5): " .. tostring(tok))
                end
            end
            if not any then
                say("usage: rftargetmove [x=amount] [y=amount] [z=amount] [yaw=amount] [pitch=amount] [roll=amount] [scale=amount] -- give only the ones you want to change, e.g. 'rftargetmove x=5 yaw=90'. Every value is a delta added to the target's CURRENT value, not an absolute.")
                return true
            end
            local parts = {}
            if deltas.x or deltas.y or deltas.z then
                local ok, loc = pcall(function() return target:K2_GetActorLocation() end)
                if ok and loc then
                    local newLoc = { X = loc.X + (deltas.x or 0), Y = loc.Y + (deltas.y or 0), Z = loc.Z + (deltas.z or 0) }
                    local okSet = pcall(function() target:K2_SetActorLocation(newLoc, false, {}, false) end)
                    parts[#parts + 1] = string.format("position -> (%.1f, %.1f, %.1f): %s", newLoc.X, newLoc.Y, newLoc.Z, tostring(okSet))
                else
                    parts[#parts + 1] = "position: could not read current location."
                end
            end
            if deltas.yaw or deltas.pitch or deltas.roll then
                local ok, rot = pcall(function() return target:K2_GetActorRotation() end)
                if ok and rot then
                    local newRot = { Pitch = rot.Pitch + (deltas.pitch or 0), Yaw = rot.Yaw + (deltas.yaw or 0), Roll = rot.Roll + (deltas.roll or 0) }
                    local okSet = pcall(function() target:K2_SetActorRotation(newRot, false) end)
                    parts[#parts + 1] = string.format("rotation -> Pitch=%.1f Yaw=%.1f Roll=%.1f: %s", newRot.Pitch, newRot.Yaw, newRot.Roll, tostring(okSet))
                else
                    parts[#parts + 1] = "rotation: could not read current rotation."
                end
            end
            if deltas.scale then
                local ok, scale = pcall(function() return target:GetActorScale3D() end)
                if ok and scale then
                    local s = deltas.scale
                    local newScale = { X = scale.X + s, Y = scale.Y + s, Z = scale.Z + s }
                    local okSet = pcall(function() target:K2_SetActorScale3D(newScale) end)
                    parts[#parts + 1] = string.format("scale -> (%.3f, %.3f, %.3f): %s", newScale.X, newScale.Y, newScale.Z, tostring(okSet))
                else
                    parts[#parts + 1] = "scale: could not read current scale."
                end
            end
            say(table.concat(parts, " | "))
            return true
        end)
    end)
    registerCmdInfo("rftargetmove", "rftargetmove [x=amount] [y=amount] [z=amount] [yaw=amount] [pitch=amount] [roll=amount] [scale=amount]",
        "Nudges your current target (set by rftarget) by the given amounts -- position in world units (x/y/z), rotation in degrees (yaw/pitch/roll), and uniform scale (scale). Every value is a DELTA added to whatever the target already has, not an absolute value, and any parameter you don't include is left completely untouched -- so 'rftargetmove x=5' moves it 5 units on X only, without needing to also specify y=0 z=0 etc. Combine as many as you like in one call, e.g. 'rftargetmove x=10 z=-5 yaw=45 scale=0.2'. Negative amounts work the same way, e.g. 'rftargetmove scale=-0.1' shrinks it slightly.")
end

----------------------------------------------------------------------------------------------
-- rfnudge -- vertical movement while rfnoclip is on. Flying mode has no native ascend/descend
-- key bound in this game, so normal movement input only moves you horizontally -- confirmed
-- live. This is a direct world-offset write, queued through the same poll-loop pattern as
-- rfsetweather/rfsettime (a proven-safe pattern for touching the pawn/world from here, rather
-- than risk a new one).
----------------------------------------------------------------------------------------------

local pendingNudge = nil
if ExecuteWithDelay then
    local function nudgePollLoop()
        ExecuteWithDelay(200, function()
            if pendingNudge ~= nil then
                local req = pendingNudge
                pendingNudge = nil
                ExecuteInGameThread(function()
                    pcall(function()
                        local pc = UEHelpers.GetPlayerController()
                        local pawn = pc and pc:IsValid() and pc.Pawn
                        if not (pawn and pawn:IsValid()) then
                            print("[WindroseConsoleTools] [rfnudge] no player pawn found.\n")
                            return
                        end
                        local delta = (req.dir == "up") and req.amount or -req.amount
                        local loc = pawn:K2_GetActorLocation()
                        pawn:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = loc.Z + delta }, false, {}, false)
                        print(string.format("[WindroseConsoleTools] [rfnudge] moved %s by %.1f.\n", req.dir, req.amount))
                    end)
                end)
            end
            nudgePollLoop()
        end)
    end
    nudgePollLoop()
end

if RegisterConsoleCommandHandler then
    pcall(function()
        RegisterConsoleCommandHandler("rfnudge", function(FullCommand, Parameters, Ar)
            local function say(msg)
                print("[WindroseConsoleTools] [rfnudge] " .. msg .. "\n")
                pcall(function()
                    if type(Ar) == "userdata" and Ar.type and Ar:type() == "FOutputDevice" then Ar:Log(msg) end
                end)
            end
            local dir = (Parameters and Parameters[1] or "up"):lower()
            if dir ~= "up" and dir ~= "down" then
                say("usage: rfnudge <up|down> [amount]")
                return true
            end
            local amount = tonumber(Parameters and Parameters[2]) or 100.0
            pendingNudge = { dir = dir, amount = amount }
            say(string.format("nudging %s by %.1f...", dir, amount))
            return true
        end)
    end)
    registerCmdInfo("rfnudge", "rfnudge <up|down> [amount]",
        "Moves your own character straight up or down by [amount] world units (default 100). This is specifically for vertical movement while rfnoclip is on -- there is no normal key bound to fly up/down in this game, so without this command you can only move horizontally while flying. Run it repeatedly to keep climbing or descending, e.g. 'rfnudge up 50' several times in a row.")
end

log("Windrose Console Tools loaded.")
