local addonName, AQ = ...

AQ.version = "1.0"
AtlasQuestieDB = AtlasQuestieDB or { enabled = true }

-- C_Timer shim for older Classic builds
if not C_Timer then
    C_Timer = {}
    function C_Timer.After(d, f)
        local fr = CreateFrame("Frame")
        local s = GetTime()
        fr:SetScript("OnUpdate", function(self)
            if GetTime() - s >= d then f() self:SetScript("OnUpdate", nil) end
        end)
    end
end

-- ============================================================
-- Completed-quest tracking
--
-- IMPORTANT: IsQuestFlaggedCompleted / C_QuestLog.IsQuestFlaggedCompleted
-- do NOT exist on the 3.3.5 client -- that function wasn't added until
-- Mists of Pandaria (patch 5.0.4), two expansions later. Using it here
-- would crash exactly like the original SetShown bug.
--
-- The correct 3.3.5-era API is GetQuestsCompleted(), added in patch
-- 3.3.0 (the same patch line as 3.3.5), which returns a table keyed by
-- questId for every quest completed in the character's lifetime. Before
-- patch 5.0.4, this requires calling QueryQuestsCompleted() first and
-- waiting for the QUEST_QUERY_COMPLETE event, since the data is fetched
-- from the server asynchronously and isn't available immediately.
-- ============================================================

AQ.completedQuestsCache = nil -- nil = not yet loaded; table once loaded

local function AQ_RefreshCompletedQuests()
    if GetQuestsCompleted then
        AQ.completedQuestsCache = GetQuestsCompleted() or {}
    end
end

local function AQ_IsQuestCompleted(questId)
    if not (questId and AQ.completedQuestsCache) then return false end
    return AQ.completedQuestsCache[questId] == true
end


local FACTION_COLOR = {
    A = "|cFF3399FF[A]|r ",
    H = "|cFFFF3333[H]|r ",
}

local QUALITY_COLOR = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
}

-- ============================================================
-- World map opener — Classic-compatible
--
-- WorldMapFrame_SetWorldMap / C_Map.SetFallbackWorldMapID do NOT
-- exist on the 3.3.5 client (those are retail-only APIs), so
-- using them here was a no-op and the map just opened on
-- whatever zone it last displayed (usually the player's current
-- zone). The real 3.3.5/Classic API for this is:
--   SetMapZoom(continentIndex, zoneIndex)
--
-- IMPORTANT: on THIS client generation, GetMapContinents() and
-- GetMapZones(continentIndex) return NAMES ONLY -- e.g.
--   GetMapZones(2) -> "Alterac Mountains", "Arathi Highlands", ...
-- with NO numeric zone ID interleaved between names. The commonly-
-- quoted "zoneID_1, zoneName_1, zoneID_2, zoneName_2, ..." shape
-- (which earlier code here assumed) was only added in Patch 6.0.2
-- (Warlords of Draenor) -- confirmed both by period-correct vanilla
-- API docs and by directly testing on this client (the interleaved-
-- pair assumption produced exactly the "names where IDs should be"
-- corruption pattern you'd expect from reading a plain name array
-- two-at-a-time). continentIndex/zoneIndex for SetMapZoom are simply
-- the 1-based POSITION of a name in these plain arrays -- there is no
-- separate numeric ID to extract at all.
-- ============================================================

-- Finds (continentIndex, zoneIndex) for a given zone name by
-- scanning the live client zone list. Returns nil, nil if not found.
-- Comparison is normalized (case/punctuation-insensitive) because our
-- zone name may come from title-casing a Questie constant name (e.g.
-- "Un Goro Crater" derived from UN_GORO_CRATER vs. the client's
-- "Un'Goro Crater") rather than the client's exact display string.
local function AQ_NormalizeZoneName(s)
    if not s then return nil end
    return s:lower():gsub("[^%a%d]", "")
end

-- Returns continentN, zoneN, isSubzoneMatch
local function AQ_FindZoneIndices(zoneName)
    if not (zoneName and GetMapContinents and GetMapZones) then return nil, nil end

    local target = AQ_NormalizeZoneName(zoneName)
    local continentNames = { GetMapContinents() }

    -- Pass 1: top-level zones (exact zone, e.g. "Undercity", "Silverpine Forest").
    -- Names only -- no interleaved IDs on this client -- so #continentNames
    -- IS the count, and each entry's own position is its index.
    for continentN = 1, #continentNames do
        local zoneNames = { GetMapZones(continentN) }
        for zoneN = 1, #zoneNames do
            if AQ_NormalizeZoneName(zoneNames[zoneN]) == target then
                return continentN, zoneN, false
            end
        end
    end

    -- Pass 2: subzones/landmarks within each zone (e.g. "The Sepulcher"
    -- inside Silverpine Forest). Falls back to the PARENT zone's indices,
    -- since SetMapZoom has no separate subzone-level call.
    --
    -- GetMapSubzones' exact shape on this client isn't confirmed (no
    -- period-correct vanilla doc found), so we detect it defensively:
    -- it's called with the zone NAME (matching the names-only pattern
    -- of its siblings on this client), and we treat every returned
    -- value as a name to compare directly rather than assuming any
    -- particular pairing.
    if GetMapSubzones then
        for continentN = 1, #continentNames do
            local zoneNames = { GetMapZones(continentN) }
            for zoneN = 1, #zoneNames do
                local ok, subzones = pcall(function() return { GetMapSubzones(zoneNames[zoneN]) } end)
                if ok and subzones then
                    for _, subValue in ipairs(subzones) do
                        if type(subValue) == "string" and AQ_NormalizeZoneName(subValue) == target then
                            return continentN, zoneN, true
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end

-- Shows a temporary marker on the world map at the given percent
-- position (0-100 each, matching Questie's coordinate convention),
-- relative to WorldMapDetailFrame -- the same frame GetPlayerMapPosition
-- positions are relative to, which is the standard convention used by
-- coordinate-display addons on this client. Auto-hides after ~10 seconds.
--
-- Built from solid-color textures (SetTexture(r,g,b,a), no file path)
-- rather than a built-in icon file, since we couldn't confirm an exact
-- in-client texture path for a ping-style graphic and didn't want to
-- repeat the "guessed a name, it silently does nothing" mistake from
-- elsewhere in this addon.
local AQ_pingHideTimer = nil
local function AQ_ShowMapPing(x, y)
    if not (WorldMapDetailFrame and type(x) == "number" and type(y) == "number") then return end

    if not AQ.MapPing then
        local ping = CreateFrame("Frame", "AtlasQuestieMapPing", WorldMapDetailFrame)
        ping:SetSize(24, 24)
        ping:SetFrameStrata("TOOLTIP")

        -- Pulsating "?" label. Using a large, outlined font so it is
        -- clearly visible against both green terrain and blue water.
        local label = ping:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        label:SetText("?")
        label:SetTextColor(1, 0.9, 0, 1)   -- bright gold
        label:SetPoint("CENTER", ping, "CENTER", 0, 0)
        ping.label = label

        ping.pulseElapsed = 0
        ping:SetScript("OnUpdate", function(self, elapsed)
            self.pulseElapsed = self.pulseElapsed + elapsed
            local t = math.abs(math.sin(self.pulseElapsed * 2.0))
            -- Size: oscillates 14..26
            local size = 14 + 12 * t
            self.label:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
            -- Color: crossfades gold (1, 0.9, 0) <-> red (1, 0.1, 0.1)
            -- t=1 -> gold, t=0 -> red
            local g = 0.1 + 0.8 * t   -- green channel
            local b = 0.1 - 0.1 * t   -- blue channel (0 for gold, tiny for red)
            self.label:SetTextColor(1, g, math.max(0, b))
        end)

        AQ.MapPing = ping
    end

    local ping = AQ.MapPing
    local w, h = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
    ping:ClearAllPoints()
    ping:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", (x / 100) * w, -(y / 100) * h)
    ping:Show()

    AQ_pingHideTimer = (AQ_pingHideTimer or 0) + 1
    local myTimer = AQ_pingHideTimer
    C_Timer.After(10, function()
        if AQ_pingHideTimer == myTimer and AQ.MapPing then
            AQ.MapPing:Hide()
        end
    end)
end

-- pingX, pingY are optional raw percent coordinates (0-100) for a
-- temporary marker at the pickup location, shown once the zoom succeeds.
local function AQ_OpenMapToZone(zoneName, coordStr, pingX, pingY)
    if not WorldMapFrame then return end

    -- No coordStr means AQ_GetNpcZoneCoords determined there's no real
    -- outdoor map position (Questie's -1,-1 sentinel for dungeon-interior
    -- NPCs/objects). There's nowhere meaningful to navigate to, but stay
    -- silent is worse than useless -- it looks like a broken click. Say
    -- so clearly instead.
    if not coordStr then
        local who = zoneName and (" \"" .. zoneName .. "\"") or ""
        print("|cFFFFD200AtlasQuestie:|r" .. who .. " has no position on the outdoor world map (it's inside a dungeon, with no outdoor pickup point).")
        return
    end

    -- Build a helpful chat message
    local msg = "|cFFFFD200AtlasQuestie:|r"
    if zoneName then msg = msg .. " " .. zoneName end
    msg = msg .. " (" .. coordStr .. ")"
    print(msg)

    -- IMPORTANT ORDERING: show the frame BEFORE calling SetMapZoom, not
    -- after. WorldMapFrame's own OnShow handler (WorldMapFrame_OnShow in
    -- Blizzard's FrameXML) unconditionally calls SetMapToCurrentZone(),
    -- which resets the displayed zone to wherever the PLAYER currently
    -- is. That handler only fires on the hidden->shown transition and
    -- runs synchronously inside :Show(), so by the time ShowUIPanel
    -- returns here, that reset has already happened -- meaning any
    -- SetMapZoom call made BEFORE this point gets silently overwritten
    -- a moment later. Calling SetMapZoom after the frame is shown avoids
    -- this entirely.
    if not WorldMapFrame:IsShown() then
        ShowUIPanel(WorldMapFrame)
    end

    local continentN, zoneN, isSubzone = AQ_FindZoneIndices(zoneName)
    if continentN and SetMapZoom then
        SetMapZoom(continentN, zoneN)
        if isSubzone then
            print("|cFFFFD200AtlasQuestie:|r \"" .. zoneName .. "\" is a subzone - opened its parent zone on the map.")
        elseif pingX and pingY then
            AQ_ShowMapPing(pingX, pingY)
        end
    elseif zoneName then
        print("|cFFFF0000AtlasQuestie:|r couldn't find \"" .. zoneName .. "\" on the world map (name may not match the client's zone list).")
    end
end

-- ============================================================
-- Popup frame helper (Classic-safe, no BasicFrameTemplateWithInset)
-- ============================================================

local function AQ_CreatePopupFrame(name, parent, w, h, titleText)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    f:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText(titleText or "")
    f.titleText = title

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    return f
end

-- ============================================================
-- Coord-link button factory
-- ============================================================

local function AQ_MakeCoordButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(16)
    btn:EnableMouse(true)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetJustifyH("LEFT")
    btn.fs = fs

    -- Highlight on hover
    btn:SetScript("OnEnter", function(self)
        self.fs:SetTextColor(0.4, 0.8, 1)
        if self.npcName or self.coords then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.npcName then
                GameTooltip:AddLine(self.npcName, 1, 1, 0)
            end
            if self.zone then
                GameTooltip:AddLine(self.zone, 0.7, 0.7, 0.7)
            end
            if self.coords then
                GameTooltip:AddLine("Coords: " .. self.coords, 1, 1, 1)
            end
            GameTooltip:AddLine("Left click to view on world map", 0.4, 0.8, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.fs:SetTextColor(1, 1, 1)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        AQ_OpenMapToZone(self.zone, self.coords, self.x, self.y)
    end)
    btn:Hide()
    return btn
end

-- ============================================================
-- Item icon factory (32×32 with quality border + hover tooltip)
-- ============================================================

local ICON_SIZE = 32

local function AQ_MakeItemIcon(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:Hide()

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    btn.tex = tex

    btn:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        -- SetHyperlink with a minimal item string gives the full client
        -- tooltip including stats, item level, and shift-key comparison
        -- with currently equipped gear -- all automatic, no manual
        -- stat-building required.
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemId .. ":0:0:0:0:0:0:0")
        if self.isChoice then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Choice reward - pick one", 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- ============================================================
-- Questie data accessors
-- ============================================================

local function AQ_ExtractDescription(q)
    if type(q) ~= "table" then return nil end
    if type(q.description)    == "string" and q.description    ~= "" then return q.description end
    if type(q.Description)    == "string" and q.Description    ~= "" then return q.Description end
    if type(q.objectivesText) == "table" then
        local lines = {}
        for _, line in ipairs(q.objectivesText) do
            if type(line) == "string" then table.insert(lines, line) end
        end
        if #lines > 0 then return table.concat(lines, "\n") end
    end
    if type(q.ObjectiveData) == "table" then
        local lines = {}
        for _, obj in pairs(q.ObjectiveData) do
            if type(obj) == "table" then
                local t = obj.Text or obj.description or obj.text
                if type(t) == "string" then table.insert(lines, t) end
            end
        end
        if #lines > 0 then return table.concat(lines, "\n") end
    end
    return nil
end

-- Returns the QuestieDB module, or nil if Questie isn't loaded/ready yet.
local function AQ_GetQuestieDB()
    if not QuestieLoader then return nil end
    local ok, QuestieDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if ok then return QuestieDB end
    return nil
end

local function AQ_GetQuestieQuest(QuestieDB, questId)
    if not QuestieDB then return nil end
    if type(QuestieDB.GetQuest) == "function" then
        local ok, q = pcall(QuestieDB.GetQuest, QuestieDB, questId)
        if ok and q then return q, "GetQuest(self,id)" end
        ok, q = pcall(QuestieDB.GetQuest, questId)
        if ok and q then return q, "GetQuest(id)" end
    end
    if type(QuestieDB.questData) == "table" and type(QuestieDB.questKeys) == "table" then
        local raw = QuestieDB.questData[questId]
        if raw then
            local q = { id = questId }
            for fieldName, idx in pairs(QuestieDB.questKeys) do q[fieldName] = raw[idx] end
            return q, "questData+questKeys"
        end
    end
    if type(QuestieDB.QueryQuestSingle) == "function" then
        local ok, name = pcall(QuestieDB.QueryQuestSingle, questId, "name")
        if ok and name then
            local q = { id = questId, name = name }
            for _, f in ipairs({
                "description","objectivesText","level","requiredLevel","questLevel",
                "requiredRaces","startedBy","finishedBy","preQuestSingle","preQuestGroup",
                "nextQuestInChain","parentQuest",
            }) do
                local ok2, val = pcall(QuestieDB.QueryQuestSingle, questId, f)
                if ok2 then q[f] = val end
            end
            return q, "QueryQuestSingle"
        end
    end
    return nil, "no accessor matched"
end

-- Questie's own schema stores startedBy/finishedBy as a 3-slot table:
-- {creatureIds, objectIds, itemIds} (documented in Questie's questDB.lua
-- as creatureStart/objectStart/itemStart). AQ_FirstSubId pulls the first
-- id out of whichever slot we ask for, so we can resolve a quest starter
-- whether it's an NPC, a world object (chest/body), or an item (e.g. a
-- journal looted off a body that you then use to start the quest).
local function AQ_FirstSubId(t, idx)
    if type(t) ~= "table" then return nil end
    local ids = t[idx]
    if type(ids) == "table" and ids[1] then return ids[1] end
    return nil
end

-- Fetches an object's display name from Questie's own object record.
local function AQ_GetObjectName(QuestieDB, objectId)
    local obj = AQ_GetObject(QuestieDB, objectId)
    if not obj then return nil end
    return obj.name or obj.Name
end

-- Fetches an item's display name from Questie's item DB, falling back
-- to the client's own item cache (GetItemInfo) if Questie doesn't have
-- a name field cached yet.
local function AQ_GetItemName(QuestieDB, itemId)
    if not (QuestieDB and itemId) then return nil end
    if type(QuestieDB.GetItem) == "function" then
        local ok, item = pcall(QuestieDB.GetItem, QuestieDB, itemId)
        if not (ok and item) then ok, item = pcall(QuestieDB.GetItem, itemId) end
        if ok and item and (item.name or item.Name) then return item.name or item.Name end
    end
    if type(QuestieDB.QueryItemSingle) == "function" then
        local ok, name = pcall(QuestieDB.QueryItemSingle, itemId, "name")
        if ok and name then return name end
    end
    if GetItemInfo then
        local name = GetItemInfo(itemId)
        if name then return name end
    end
    return nil
end

local function AQ_FirstNpcId(t)
    if type(t) ~= "table" then return nil end
    local npcIds = t[1]
    if type(npcIds) == "table" and npcIds[1] then return npcIds[1] end
    return nil
end

-- Fetches the full live NPC table from Questie (name, friendlyToFaction, spawns, ...)
local function AQ_GetNpc(QuestieDB, npcId)
    if not (QuestieDB and npcId and npcId ~= 0) then return nil end
    if type(QuestieDB.GetNPC) ~= "function" then return nil end
    local ok, npc = pcall(QuestieDB.GetNPC, QuestieDB, npcId)
    if not (ok and npc) then ok, npc = pcall(QuestieDB.GetNPC, npcId) end
    if ok and npc then return npc end
    return nil
end

-- Cached import of Questie's ZoneDB module, shared by anything that
-- needs it (zone-name lookup, dungeon-entrance fallback, ...).
local AQ_zoneDBModule = nil
local AQ_zoneDBTried = false
local function AQ_GetZoneDBModule()
    if not AQ_zoneDBTried then
        AQ_zoneDBTried = true
        if QuestieLoader then
            local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
            if ok and mod then AQ_zoneDBModule = mod end
        end
    end
    return AQ_zoneDBModule
end

-- Reverse lookup: Questie zoneId (an AreaID) -> readable zone name.
--
-- Questie's ZoneDB module exposes zoneIDs.<CONSTANT_NAME> = <id> (e.g.
-- zoneIDs.ICECROWN = 485, confirmed from Questie's own source). There is
-- no confirmed "get zone name string" function in Questie's API, so
-- rather than guess at one (and risk silently calling something that
-- doesn't exist), we build the reverse mapping ourselves from data we
-- KNOW exists, title-casing the constant name into a readable string
-- ("TIRISFAL_GLADES" -> "Tirisfal Glades"). Built once and cached.
local AQ_zoneIdToNameCache = nil
local function AQ_ZoneIdToName(zoneId)
    if not zoneId then return nil end

    if not AQ_zoneIdToNameCache then
        AQ_zoneIdToNameCache = {}
        local ZoneDBModule = AQ_GetZoneDBModule()
        if ZoneDBModule and type(ZoneDBModule.zoneIDs) == "table" then
            for constName, id in pairs(ZoneDBModule.zoneIDs) do
                if type(constName) == "string" and type(id) == "number" then
                    -- "TIRISFAL_GLADES" -> "Tirisfal Glades"
                    local words = {}
                    for word in constName:gmatch("[^_]+") do
                        table.insert(words, word:sub(1,1):upper() .. word:sub(2):lower())
                    end
                    AQ_zoneIdToNameCache[id] = table.concat(words, " ")
                end
            end
        end
    end

    return AQ_zoneIdToNameCache[zoneId]
end

-- For an NPC/object whose only known point is Questie's {-1,-1} "no real
-- position" sentinel (i.e. it lives entirely inside a dungeon interior),
-- Questie itself doesn't leave that as a dead end -- its own map-icon
-- code (QuestieQuest.lua) falls back to ZoneDB:GetDungeonLocation(zone)
-- to find that dungeon's entrance point on the outdoor continent map,
-- and draws the icon there instead. We do the exact same lookup, so an
-- NPC entirely inside a dungeon (like Willix the Importer, NPC 4508 in
-- Razorfen Kraul) still resolves to a real, correct pin at the dungeon
-- entrance -- straight from Questie's own data, not curated by us.
local function AQ_GetDungeonEntrance(interiorZoneId)
    if not interiorZoneId then return nil, nil, nil end
    local ZoneDBModule = AQ_GetZoneDBModule()
    if not (ZoneDBModule and type(ZoneDBModule.GetDungeonLocation) == "function") then
        return nil, nil, nil
    end
    local ok, dungeonLocation = pcall(ZoneDBModule.GetDungeonLocation, ZoneDBModule, interiorZoneId)
    if not (ok and dungeonLocation) then
        ok, dungeonLocation = pcall(ZoneDBModule.GetDungeonLocation, interiorZoneId)
    end
    if not (ok and dungeonLocation and dungeonLocation[1]) then return nil, nil, nil end

    local entry = dungeonLocation[1]
    local entranceZoneId, x, y = entry[1], entry[2], entry[3]
    if type(x) == "number" and type(y) == "number" then
        return entranceZoneId, x, y
    end
    return nil, nil, nil
end


-- Picks one zone/coord pair out of an NPC's live Questie spawn data and
-- formats it the way the rest of the UI expects ("XX.X, YY.Y").
--
-- Questie's exact spawn-data shape has varied across versions/forks, so
-- this checks several known shapes defensively rather than assuming one:
--   1) npc.spawns[zoneId] = { {x,y}, {x,y}, ... }      (zone is the table key)
--   2) npc.spawns[zoneId] = { {x,y,mapId}, ... }        (point also carries an id)
--   3) npc.zone / npc.zoneId / npc.Zone                 (a flat top-level field)
--
-- An NPC can have spawn points in MULTIPLE zones at once -- e.g. Willix
-- the Importer (NPC 4508) has a point inside Razorfen Kraul's interior
-- (which Questie marks with its {-1,-1} "no real map position" sentinel,
-- since dungeon interiors have no outdoor coordinate space) AND a
-- separate point right at the dungeon entrance outdoors (the one
-- Questie's own "Show on Map" button uses). Lua's `pairs()` iterates
-- spawns in no guaranteed order, so we must check every zone and every
-- point in it for a real coordinate rather than stopping at whichever
-- one we happen to reach first -- otherwise landing on the sentinel
-- first makes a perfectly good outdoor point look like it doesn't exist.
local function AQ_GetNpcZoneCoords(QuestieDB, npc)
    if not npc then return nil, nil end

    -- Shape 3 first: a flat zone field directly on the NPC, independent of
    -- however spawns are nested. If present, prefer it as the most direct
    -- source of "what zone is this NPC actually in".
    local flatZoneId = npc.zoneId or npc.ZoneID or npc.zone or npc.Zone
    if type(flatZoneId) == "string" then
        -- Some versions may store the name directly as a string already.
        return nil, flatZoneId
    end

    local spawns = npc.spawns or npc.Spawns
    if type(spawns) ~= "table" then
        if type(flatZoneId) == "number" then
            local entranceZoneId, ex, ey = AQ_GetDungeonEntrance(flatZoneId)
            if entranceZoneId and ex and ey then
                local coordStr = string.format("%.1f, %.1f", ex, ey)
                return coordStr, AQ_ZoneIdToName(entranceZoneId), ex, ey
            end
            return nil, AQ_ZoneIdToName(flatZoneId)
        end
        return nil, nil
    end

    -- Scan every zone and every point in it; remember the first sentinel
    -- zone we see (id + name) as a fallback in case no zone anywhere has
    -- a real coordinate.
    local fallbackZoneName = nil
    local fallbackZoneId = nil
    for zoneId, points in pairs(spawns) do
        if type(points) == "table" then
            for _, point in pairs(points) do
                if type(point) == "table" then
                    local x, y = point[1], point[2]
                    -- Shape 2: a 3rd element on the point itself can be a
                    -- per-point zone/map id, which takes priority over the
                    -- outer table key if present and numeric.
                    local pointZoneId = point[3]
                    local resolvedZoneId = (type(pointZoneId) == "number" and pointZoneId) or zoneId
                    local zoneName = AQ_ZoneIdToName(resolvedZoneId)
                    if type(x) == "number" and type(y) == "number" then
                        -- Questie uses {-1, -1} as a sentinel meaning "no
                        -- real map position" -- typically for NPCs inside
                        -- dungeon interiors. Skip it and keep looking
                        -- instead of giving up, since the SAME npc may
                        -- have a real point in another zone.
                        if x >= 0 and y >= 0 then
                            local coordStr = string.format("%.1f, %.1f", x, y)
                            -- 3rd/4th return values: raw percent x,y
                            -- (0-100), for callers that need to plot an
                            -- exact point (e.g. the temporary map ping)
                            -- rather than just display text.
                            return coordStr, zoneName, x, y
                        end
                        fallbackZoneName = fallbackZoneName or zoneName
                        fallbackZoneId   = fallbackZoneId   or resolvedZoneId
                    end
                end
            end
        end
    end

    -- No real point anywhere in spawns -- this NPC lives entirely inside
    -- a dungeon interior with no outdoor coordinate space of its own
    -- (exactly Questie's {-1,-1} case). Ask Questie for that dungeon's
    -- entrance point, the same fallback Questie's own map-icon code uses.
    if fallbackZoneId then
        local entranceZoneId, ex, ey = AQ_GetDungeonEntrance(fallbackZoneId)
        if entranceZoneId and ex and ey then
            local coordStr = string.format("%.1f, %.1f", ex, ey)
            return coordStr, AQ_ZoneIdToName(entranceZoneId), ex, ey
        end
    end

    if fallbackZoneName then
        return nil, fallbackZoneName
    end

    -- Numeric flat zone id as a last resort if no usable coords were found
    -- in spawns but we do have an id to name.
    if type(flatZoneId) == "number" then
        return nil, AQ_ZoneIdToName(flatZoneId)
    end

    return nil, nil
end

-- Fetches the Questie object record for a game object (chest, journal,
-- interactable body, etc.) by its object ID. Same pattern as AQ_GetNpc.
local function AQ_GetObject(QuestieDB, objectId)
    if not (QuestieDB and objectId and objectId ~= 0) then return nil end
    if type(QuestieDB.GetObject) ~= "function" then return nil end
    local ok, obj = pcall(QuestieDB.GetObject, QuestieDB, objectId)
    if not (ok and obj) then ok, obj = pcall(QuestieDB.GetObject, objectId) end
    if ok and obj then return obj end
    return nil
end

-- Gets spawn coordinates for a game object. The spawns table format is
-- identical to NPC spawns, so we can reuse AQ_GetNpcZoneCoords logic.
local function AQ_GetObjectZoneCoords(QuestieDB, objectId)
    local obj = AQ_GetObject(QuestieDB, objectId)
    if not obj then return nil, nil end
    -- Objects don't have a flat zoneID field; go straight to spawns.
    local spawns = obj.spawns or obj.Spawns
    if type(spawns) ~= "table" then return nil, nil end
    for zoneId, points in pairs(spawns) do
        if type(points) == "table" and points[1] then
            local point = points[1]
            if type(point) == "table" then
                local x, y = point[1], point[2]
                local pointZoneId = point[3]
                local resolvedZoneId = (type(pointZoneId) == "number" and pointZoneId) or zoneId
                local zoneName = AQ_ZoneIdToName(resolvedZoneId)
                if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
                    local coordStr = string.format("%.1f, %.1f", x, y)
                    return coordStr, zoneName, x, y
                end
            end
        end
    end
    return nil, nil
end

-- Resolves an item's world pickup location (for items found on the
-- ground/on a body rather than bought or dropped by a killed monster)
-- by reading QuestieDB:GetItem's Sources list and looking up the first
-- object-type source's spawn coordinates. Tries several plausible field
-- name variants defensively, since exact Questie internals have proven
-- inconsistent across forks/versions throughout this addon's development.
local function AQ_GetItemZoneCoords(QuestieDB, itemId)
    if not (QuestieDB and itemId) then return nil, nil end
    if type(QuestieDB.GetItem) ~= "function" then return nil, nil end

    local ok, item = pcall(QuestieDB.GetItem, QuestieDB, itemId)
    if not (ok and item) then ok, item = pcall(QuestieDB.GetItem, itemId) end
    if not (ok and item) then return nil, nil end

    local sources = item.Sources or item.sources
    if type(sources) ~= "table" then return nil, nil end

    for _, source in pairs(sources) do
        if type(source) == "table" then
            local sType = source.Type or source.type
            local sId   = source.Id or source.id or source.ID
            if sType and sId then
                local typeLower = tostring(sType):lower()
                if typeLower == "object" or typeLower == "gameobject" then
                    local coordStr, zoneName, x, y = AQ_GetObjectZoneCoords(QuestieDB, sId)
                    if coordStr then return coordStr, zoneName, x, y end
                elseif typeLower == "monster" or typeLower == "npc" then
                    local npc = AQ_GetNpc(QuestieDB, sId)
                    local coordStr, zoneName, x, y = AQ_GetNpcZoneCoords(QuestieDB, npc)
                    if coordStr then return coordStr, zoneName, x, y end
                end
            end
        end
    end

    return nil, nil
end


-- Questie data — never a hardcoded per-quest faction.
--
-- Primary signal: the quest's own requiredRaces bitmask (set server-side,
-- exposed by Questie as q.requiredRaces). Falls back to the starter NPC's
-- friendlyToFaction if the quest itself has no race restriction (e.g. a
-- faction-neutral quest whose only quest-giver instance happens to be
-- reachable by one faction).
local function AQ_GetQuestFaction(QuestieDB, q, starterNpc)
    local raceMask = q and (q.requiredRaces or q.RequiredRaces)
    if type(raceMask) == "number" and raceMask > 0 and QuestieDB and QuestieDB.raceKeys then
        local allAlliance = QuestieDB.raceKeys.ALL_ALLIANCE
        local allHorde    = QuestieDB.raceKeys.ALL_HORDE
        if type(allAlliance) == "number" and raceMask == allAlliance then
            return "A"
        elseif type(allHorde) == "number" and raceMask == allHorde then
            return "H"
        elseif type(allAlliance) == "number" and type(allHorde) == "number" then
            -- Partial bitmask: still tells us which side(s) it's restricted to.
            local bit = bit32 or bit
            if bit and bit.band then
                local touchesAlliance = bit.band(raceMask, allAlliance) ~= 0
                local touchesHorde    = bit.band(raceMask, allHorde) ~= 0
                if touchesAlliance and not touchesHorde then return "A" end
                if touchesHorde and not touchesAlliance then return "H" end
            end
        end
    end

    -- No usable race restriction on the quest itself — fall back to the
    -- starter NPC's faction, if Questie tells us one.
    local friendly = starterNpc and (starterNpc.friendlyToFaction or starterNpc.FriendlyToFaction)
    if friendly == "A" or friendly == "H" then
        return friendly
    end
    return nil
end

-- Finds a quest's index in the player's quest log, or nil if the quest
-- isn't currently in the log. Uses the questID field of GetQuestLogTitle,
-- which has been available since patch 3.3.0 (so it works on 3.3.5).
local function AQ_FindQuestLogIndex(questId)
    if not (questId and GetNumQuestLogEntries and GetQuestLogTitle) then return nil end
    local numEntries = GetNumQuestLogEntries()
    if not numEntries then return nil end
    for i = 1, numEntries do
        -- WotLK 3.3.5 signature: questTitle, level, questTag, suggestedGroup,
        -- isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(i)
        -- (isHeader is position 5 and questID is position 9 on this client;
        -- later clients reordered this, so don't reuse these indices there.)
        local _, _, _, _, isHeader, _, _, _, logQuestId = GetQuestLogTitle(i)
        if (not isHeader) and logQuestId == questId then
            return i
        end
    end
    return nil
end

local function AQ_IsQuestInLog(questId)
    return AQ_FindQuestLogIndex(questId) ~= nil
end

-- Fetches reward data (choice items, guaranteed items, money, xp) live
-- from the Blizzard quest-log API for a given questId.
--
-- IMPORTANT (3.3.5-specific): the optional trailing questID parameter on
-- GetQuestLogRewardInfo/GetQuestLogChoiceInfo/etc. is not reliably
-- supported on the WotLK 3.3.5 client (that convenience was added in
-- later expansions). The only behavior guaranteed to work on 3.3.5 is to
-- SelectQuestLogEntry(index) first and then call these functions with NO
-- questID argument, which is what we do here. This means rewards can only
-- be shown for quests that are currently in the player's quest log — if
-- the quest isn't in the log, we correctly show no reward data rather
-- than risk showing rewards for the wrong (currently-selected) quest.
local function AQ_GetQuestRewards(questId)
    if not questId then return nil end

    local logIndex = AQ_FindQuestLogIndex(questId)
    if not logIndex then return nil end

    if SelectQuestLogEntry then
        SelectQuestLogEntry(logIndex)
    end

    local numChoices = (GetNumQuestLogChoices and GetNumQuestLogChoices()) or 0
    local numItems    = (GetNumQuestLogRewards and GetNumQuestLogRewards()) or 0
    local money       = (GetQuestLogRewardMoney and GetQuestLogRewardMoney()) or 0
    local xp          = (GetQuestLogRewardXP and GetQuestLogRewardXP()) or 0

    if numChoices == 0 and numItems == 0 and money == 0 and xp == 0 then
        return nil
    end

    local rewards = { choice = {}, items = {}, money = money, xp = xp }

    for i = 1, numChoices do
        local name, texture, numItemsGiven, quality = GetQuestLogChoiceInfo(i)
        if name then
            table.insert(rewards.choice, {
                name    = name,
                icon    = texture,
                quality = quality,
                amount  = numItemsGiven,
            })
        end
    end

    for i = 1, numItems do
        local name, texture, numItemsGiven, quality = GetQuestLogRewardInfo(i)
        if name then
            table.insert(rewards.items, {
                name    = name,
                icon    = texture,
                quality = quality,
                amount  = numItemsGiven,
            })
        end
    end

    return rewards
end

-- ============================================================
-- Atlas selection — read which dungeon/zone is currently shown
-- in the Atlas window, using Atlas's own state.
--
-- Confirmed from Atlas's own source (Atlas_Refresh in Atlas.lua):
--   local zoneID = ATLAS_DROPDOWNS[AtlasOptions.AtlasType][AtlasOptions.AtlasZone]
-- zoneID is Atlas's internal string key for the currently selected
-- map (e.g. "ShadowfangKeep"), which is what AQ.DungeonQuestIds is
-- keyed by.
-- ============================================================

local function AQ_GetCurrentAtlasZoneID()
    if not (ATLAS_DROPDOWNS and AtlasOptions) then return nil end
    local typeList = ATLAS_DROPDOWNS[AtlasOptions.AtlasType]
    if not typeList then return nil end
    return typeList[AtlasOptions.AtlasZone]
end

-- Looks up a human-readable display name for an Atlas zoneID, using
-- Atlas's own AtlasMaps data (base.ZoneName[1] per Atlas_Refresh) so we
-- never hardcode dungeon display names ourselves.
local function AQ_GetAtlasZoneDisplayName(zoneID)
    if not (zoneID and AtlasMaps and AtlasMaps[zoneID]) then return zoneID end
    local base = AtlasMaps[zoneID]
    if type(base.ZoneName) == "table" and base.ZoneName[1] then
        return base.ZoneName[1]
    end
    return zoneID
end

-- ============================================================
-- Quest list — built entirely from live Questie data, filtered
-- to whichever dungeon is currently selected in Atlas.
-- AQ.DungeonQuestIds (AtlasQuestie_Quests.lua) supplies ONLY the
-- quest IDs per dungeon; everything else (name, level, faction)
-- is fetched fresh from Questie every time the list is built.
-- ============================================================

local function AQ_BuildQuestList()
    local content = AQ.QuestListContent
    if not content then return end

    -- Clear any previously built rows before rebuilding.
    if AQ.QuestListButtons then
        for _, btn in ipairs(AQ.QuestListButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
    end
    AQ.QuestListButtons = {}

    -- The currently-displayed quest details (if any) belong to whatever
    -- dungeon was selected before; hide them rather than leave stale
    -- info on screen after the user switches dungeons.
    AQ.CurrentQuest = nil
    AQ.SelectedQuestId = nil
    AQ.SelectedChainQuestId = nil
    AQ.DungeonAnchorQuestId = nil
    if AQ.DetailsFrame then AQ.DetailsFrame:Hide() end
    if AQ.ChainPopup then AQ.ChainPopup:Hide() end

    local zoneID = AQ_GetCurrentAtlasZoneID()
    local zoneDisplayName = AQ_GetAtlasZoneDisplayName(zoneID)

    if AQ.TitleText then
        AQ.TitleText:SetText(zoneDisplayName or "")
    end

    local questIds = zoneID and AQ.DungeonQuestIds and AQ.DungeonQuestIds[zoneID]

    if not questIds then
        -- We don't have curated data for whatever's currently selected
        -- in Atlas (or nothing is selected yet). Say so plainly instead
        -- of showing a stale or empty-looking list.
        if AQ.NoDataText then
            AQ.NoDataText:SetText("|cFF888888No quest information available" ..
                (zoneDisplayName and (" for " .. zoneDisplayName) or "") .. ".|r")
            AQ.NoDataText:Show()
        end
        content:SetHeight(100)
        return
    end

    if AQ.NoDataText then AQ.NoDataText:Hide() end

    local QuestieDB = AQ_GetQuestieDB()

    -- Gather quest data first so we can sort by level before rendering.
    local rows = {}
    for _, questId in ipairs(questIds) do
        local label = "Quest #" .. questId
        local faction = nil
        local level = nil

        if QuestieDB then
            local q = AQ_GetQuestieQuest(QuestieDB, questId)
            if q then
                label = q.name or label
                level = q.questLevel or q.level or q.QuestLevel
                local starterId = AQ_FirstNpcId(q.startedBy or q.StartedBy)
                local starterNpc = AQ_GetNpc(QuestieDB, starterId)
                faction = AQ_GetQuestFaction(QuestieDB, q, starterNpc)
            end
        end

        table.insert(rows, { id = questId, label = label, level = level, faction = faction, completed = AQ_IsQuestCompleted(questId), inLog = AQ_IsQuestInLog(questId) })
    end

    -- Filter by the selected faction. Quests with no determinable
    -- faction (true neutral quests, e.g. "Smart Drinks") always show;
    -- quests with a determined faction only show if it matches the
    -- currently selected filter.
    local activeFaction = AtlasQuestieDB.factionFilter
    if activeFaction then
        local filtered = {}
        for _, row in ipairs(rows) do
            if (not row.faction) or row.faction == activeFaction then
                table.insert(filtered, row)
            end
        end
        rows = filtered
    end

    if #rows == 0 then
        if AQ.NoDataText then
            local factionName = (activeFaction == "A") and "Alliance" or "Horde"
            AQ.NoDataText:SetText("|cFF888888No " .. factionName .. " quests for" ..
                (zoneDisplayName and (" " .. zoneDisplayName) or " this dungeon") .. ".|r")
            AQ.NoDataText:Show()
        end
        content:SetHeight(100)
        return
    end

    -- Sort by required level, lowest to highest. Quests whose level
    -- couldn't be determined (Questie not loaded/quest not found) sort
    -- to the end rather than being guessed at as level 0.
    table.sort(rows, function(a, b)
        if a.level and b.level then
            if a.level ~= b.level then return a.level < b.level end
            return a.label < b.label -- stable-ish tiebreaker for equal levels
        elseif a.level and not b.level then
            return true
        elseif b.level and not a.level then
            return false
        else
            return a.label < b.label
        end
    end)

    for i, row in ipairs(rows) do
        local btn = CreateFrame("Button", nil, content)
        btn:SetSize(256, 22)
        btn:SetPoint("TOPLEFT", 5, -26*(i-1))
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        -- Selection glow: a soft gold overlay shown only for whichever
        -- quest is currently displayed in the details panel. Built from
        -- a solid-color texture (no file path) rather than a built-in
        -- asset, for the same reason as the map ping marker -- we
        -- couldn't confirm an exact "selected row glow" texture path on
        -- this client, so this avoids guessing at one.
        local glow = btn:CreateTexture(nil, "BACKGROUND")
        glow:SetAllPoints(btn)
        glow:SetTexture(1, 0.82, 0, 0.18)
        glow:Hide()
        btn.glow = glow

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 8, 0)
        local tag = (row.faction and FACTION_COLOR[row.faction]) or ""
        local levelStr = row.level and (row.level .. " ") or ""
        -- Colour coding: [Done] (green) for completed quests, blue name
        -- for quests currently in the player's quest log, white otherwise.
        if row.completed then
            fs:SetText("|cFF00CC00[Done]|r " .. tag .. levelStr .. "|cFF888888" .. row.label .. "|r")
        elseif row.inLog then
            fs:SetText(tag .. levelStr .. "|cFF6699FF" .. row.label .. "|r")
        else
            fs:SetText(tag .. levelStr .. "|cFFFFFFFF" .. row.label)
        end
        local questId = row.id
        btn.questId = questId
        if AQ.SelectedQuestId == questId then
            glow:Show()
        end
        btn:SetScript("OnClick", function()
            AQ.SelectedQuestId = questId
            -- Update glow on every row immediately, without a full
            -- rebuild, so the click feels instant.
            for _, otherBtn in ipairs(AQ.QuestListButtons) do
                if otherBtn.glow then
                    if otherBtn.questId == questId then
                        otherBtn.glow:Show()
                    else
                        otherBtn.glow:Hide()
                    end
                end
            end
            AQ.SelectedChainQuestId = questId  -- chain popup: glow this row
            AQ.DungeonAnchorQuestId = questId  -- chain popup: static [dungeon quest] label
            AQ.ShowQuestDetails({ id = questId })
        end)

        table.insert(AQ.QuestListButtons, btn)
    end

    content:SetHeight(math.max(100, 26 * #rows))
end


-- ============================================================
-- OnLoad — build all frames once
-- ============================================================

function AQ.OnLoad()
    if not AtlasFrame then return end

    AQ.Frame = CreateFrame("Frame", "AtlasQuestieFrame", AtlasFrame)
    AQ.Frame:SetWidth(300)
    AQ.Frame:SetHeight(343)
    AQ.Frame:SetPoint("TOPRIGHT", AtlasFrame, "TOPLEFT", -5, -10)
    AQ.Frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    AQ.Frame:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    AQ.Frame:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
    AQ.Frame:Hide()

    -- Title shows just the dungeon name, left-aligned to avoid
    -- overlapping the H/A faction buttons on the right.
    AQ.TitleText = AQ.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AQ.TitleText:SetPoint("TOPLEFT", AQ.Frame, "TOPLEFT", 10, -12)
    AQ.TitleText:SetPoint("TOPRIGHT", AQ.Frame, "TOPRIGHT", -50, -12)
    AQ.TitleText:SetJustifyH("LEFT")
    AQ.TitleText:SetText("")

    -- Faction filter toggle (H / A) -- top-right corner, near the title.
    local hordeBtn = CreateFrame("Button", "AtlasQuestieFactionH", AQ.Frame)
    hordeBtn:SetSize(20, 20)
    hordeBtn:SetPoint("TOPRIGHT", AQ.Frame, "TOPRIGHT", -28, -7)
    local hordeFs = hordeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hordeFs:SetAllPoints(hordeBtn)
    hordeFs:SetText("H")
    hordeBtn.fs = hordeFs
    hordeBtn:SetScript("OnClick", function()
        AtlasQuestieDB.factionFilter = "H"
        AQ.UpdateFactionButtons()
        AQ_BuildQuestList()
    end)
    hordeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Show Horde quests")
        GameTooltip:Show()
    end)
    hordeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AQ.FactionHordeBtn = hordeBtn

    local allianceBtn = CreateFrame("Button", "AtlasQuestieFactionA", AQ.Frame)
    allianceBtn:SetSize(20, 20)
    allianceBtn:SetPoint("LEFT", hordeBtn, "RIGHT", 1, 0)
    local allianceFs = allianceBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    allianceFs:SetAllPoints(allianceBtn)
    allianceFs:SetText("A")
    allianceBtn.fs = allianceFs
    allianceBtn:SetScript("OnClick", function()
        AtlasQuestieDB.factionFilter = "A"
        AQ.UpdateFactionButtons()
        AQ_BuildQuestList()
    end)
    allianceBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Show Alliance quests")
        GameTooltip:Show()
    end)
    allianceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AQ.FactionAllianceBtn = allianceBtn

    -- Updates the toggle buttons' appearance to reflect the currently
    -- selected faction filter: full brightness + colored for the active
    -- side, dimmed for the inactive one.
    function AQ.UpdateFactionButtons()
        local active = AtlasQuestieDB.factionFilter
        if active == "A" then
            AQ.FactionHordeBtn.fs:SetTextColor(0.5, 0.2, 0.2)
            AQ.FactionAllianceBtn.fs:SetTextColor(0.3, 0.6, 1)
        else
            -- Default to Horde-active styling if unset (shouldn't
            -- normally happen post-PLAYER_LOGIN, but fail toward a
            -- sensible default rather than showing both as dim).
            AQ.FactionHordeBtn.fs:SetTextColor(1, 0.25, 0.25)
            AQ.FactionAllianceBtn.fs:SetTextColor(0.25, 0.3, 0.45)
        end
    end
    AQ.UpdateFactionButtons()

    -- Quest list scroll
    local scroll = CreateFrame("ScrollFrame", "AtlasQuestieScroll", AQ.Frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     10, -35)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(256, 100)
    scroll:SetScrollChild(content)
    AQ.QuestListContent = content

    -- Shown instead of the quest list when the currently-selected Atlas
    -- dungeon has no curated entry in AQ.DungeonQuestIds.
    AQ.NoDataText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AQ.NoDataText:SetPoint("TOPLEFT", 5, -10)
    AQ.NoDataText:SetPoint("TOPRIGHT", -5, -10)
    AQ.NoDataText:SetJustifyH("LEFT")
    AQ.NoDataText:SetJustifyV("TOP")
    AQ.NoDataText:SetWordWrap(true)
    AQ.NoDataText:Hide()

    AQ_BuildQuestList()

    -- Detail panel -- its own independent popup-style window (movable,
    -- bordered, closable), anchored to the lower-left of the main quest
    -- list frame rather than overlapping it.
    AQ.DetailsFrame = AQ_CreatePopupFrame("AtlasQuestieDetails", AtlasFrame, 300, 260, "Quest Details")
    AQ.DetailsFrame:ClearAllPoints()
    AQ.DetailsFrame:SetPoint("TOPLEFT", AQ.Frame, "BOTTOMLEFT", 0, -1)
    AQ.DetailsFrame:Hide()

    -- Text block (quest name, levels, objectives, chain info)
    AQ.DetailsText = AQ.DetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AQ.DetailsText:SetPoint("TOPLEFT",  15, -28)
    AQ.DetailsText:SetPoint("TOPRIGHT", -15, -28)
    AQ.DetailsText:SetJustifyH("LEFT")
    AQ.DetailsText:SetJustifyV("TOP")
    AQ.DetailsText:SetWordWrap(true)

    -- Coord buttons
    AQ.StarterBtn = AQ_MakeCoordButton(AQ.DetailsFrame)
    AQ.EnderBtn   = AQ_MakeCoordButton(AQ.DetailsFrame)

    -- Reward section header
    AQ.RewardLabel = AQ.DetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    AQ.RewardLabel:SetJustifyH("LEFT")

    -- Choice/guaranteed sub-labels
    AQ.ChoiceLabel     = AQ.DetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    AQ.GuaranteedLabel = AQ.DetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    -- Item icon pool (up to 6 per section, two sections = 12 max)
    AQ.RewardIcons = {}
    for i = 1, 12 do
        AQ.RewardIcons[i] = AQ_MakeItemIcon(AQ.DetailsFrame)
    end

    -- Money + XP line
    AQ.RewardMoneyText = AQ.DetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AQ.RewardMoneyText:SetJustifyH("LEFT")

    hooksecurefunc("Atlas_OnShow", function()
        if AtlasQuestieDB.enabled then
            AQ.Frame:Show()
            -- Rebuild every time the panel is shown so quest names/levels/
            -- factions are always current (e.g. if Questie's database
            -- finished compiling after our initial build attempt).
            AQ_BuildQuestList()
        end
    end)

    -- DetailsFrame and ChainPopup are independent UIParent-anchored
    -- frames now (not children of AQ.Frame), so they no longer
    -- auto-hide when Atlas/AQ.Frame hides. Close them explicitly when
    -- Atlas itself closes, using the frame's own OnHide script rather
    -- than an Atlas_OnHide global (unconfirmed to exist / consistently
    -- named across Atlas variants).
    if AtlasFrame then
        AtlasFrame:HookScript("OnHide", function()
            if AQ.DetailsFrame then AQ.DetailsFrame:Hide() end
            if AQ.ChainPopup then AQ.ChainPopup:Hide() end
        end)
    end

    -- Atlas calls Atlas_Refresh every time the selected dungeon changes
    -- (dropdown selection, the entrance/instance switch button, or
    -- auto-select on zone change) — NOT just when the window is first
    -- shown. Hooking only Atlas_OnShow would miss every later dungeon
    -- change, so we hook Atlas_Refresh too.
    if Atlas_Refresh then
        hooksecurefunc("Atlas_Refresh", function()
            if AtlasQuestieDB.enabled then
                AQ_BuildQuestList()
            end
        end)
    end

    -- Belt-and-suspenders: also poll AtlasOptions.AtlasType/AtlasZone (the
    -- actual saved-variable state Atlas itself uses to track the current
    -- selection — confirmed from Atlas's own source) and rebuild whenever
    -- it changes. This catches dungeon switches even if a particular Atlas
    -- fork/variant doesn't route every selection change through a single
    -- hookable Atlas_Refresh call. Only runs while the Atlas window is
    -- actually shown, and checks a few times a second, so the cost is
    -- negligible.
    local watcher = CreateFrame("Frame")
    local lastType, lastZone = nil, nil
    local elapsedAccum = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        if not (AtlasFrame and AtlasFrame:IsShown() and AtlasQuestieDB.enabled) then return end
        elapsedAccum = elapsedAccum + elapsed
        if elapsedAccum < 0.2 then return end
        elapsedAccum = 0

        local curType = AtlasOptions and AtlasOptions.AtlasType
        local curZone = AtlasOptions and AtlasOptions.AtlasZone
        if curType ~= lastType or curZone ~= lastZone then
            lastType, lastZone = curType, curZone
            AQ_BuildQuestList()
        end
    end)

    print("|cFF00FF00AtlasQuestie v" .. AQ.version .. " loaded|r")
end

-- ============================================================
-- Layout renderer — call after populating all data fields
-- yOff is negative, moving down from the top of DetailsFrame.
-- ============================================================

-- A QuestRewards entry can carry only xp/money/rep/choice/items -- some
-- quests (e.g. non-main chain quests) have no entry at all, and are
-- rendered with no Rewards section.
local function AQ_HasRealRewards(rewardsData)
    if type(rewardsData) ~= "table" then return false end
    if type(rewardsData.xp) == "number" and rewardsData.xp > 0 then return true end
    if type(rewardsData.money) == "number" and rewardsData.money > 0 then return true end
    if type(rewardsData.rep) == "table" and rewardsData.rep[1] then return true end
    if type(rewardsData.choice) == "table" and rewardsData.choice[1] then return true end
    if type(rewardsData.items) == "table" and rewardsData.items[1] then return true end
    return false
end

local function AQ_RenderDetails(textStr, starterData, enderData, rewardsData, hasChain)
    AQ.DetailsText:SetText(textStr)

    -- We need to measure text height. FontStrings report height accurately
    -- only after the frame has been laid out, so we set a fixed width first.
    local frameW = AQ.DetailsFrame:GetWidth() or 300
    AQ.DetailsText:SetWidth(frameW - 30)
    local textH = AQ.DetailsText:GetStringHeight()

    local yOff = -28 - textH - 6

    -- ── Starter button ──────────────────────────────────────
    if starterData then
        local btn = AQ.StarterBtn
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  AQ.DetailsFrame, "TOPLEFT",  10, yOff)
        btn:SetPoint("TOPRIGHT", AQ.DetailsFrame, "TOPRIGHT", -10, yOff)
        btn.npcName = starterData.name
        btn.coords  = starterData.coords
        btn.zone    = starterData.zone
        btn.x       = starterData.x
        btn.y       = starterData.y
        local nameStr = starterData.name and ("|cFFFFFFFF" .. starterData.name .. "|r") or "|cFF888888Unknown|r"
        local zoneStr = starterData.zone  and (" |cFF888888- " .. starterData.zone .. "|r") or ""
        local coordStr = starterData.coords and (" |cFF88DDFF(" .. starterData.coords .. ")|r") or ""
        local mapIcon = ""
        btn.fs:SetText("|cFFFFD200Starts:|r " .. nameStr .. zoneStr .. coordStr .. mapIcon)
        btn:Show()
        yOff = yOff - 18
    else
        AQ.StarterBtn:Hide()
    end

    -- ── Ender button ────────────────────────────────────────
    if enderData then
        local btn = AQ.EnderBtn
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  AQ.DetailsFrame, "TOPLEFT",  10, yOff)
        btn:SetPoint("TOPRIGHT", AQ.DetailsFrame, "TOPRIGHT", -10, yOff)
        btn.npcName = enderData.name
        btn.coords  = enderData.coords
        btn.zone    = enderData.zone
        btn.x       = enderData.x
        btn.y       = enderData.y
        local nameStr  = enderData.name   and ("|cFFFFFFFF" .. enderData.name  .. "|r") or "|cFF888888Unknown|r"
        local zoneStr  = enderData.zone   and (" |cFF888888- " .. enderData.zone  .. "|r") or ""
        local coordStr = enderData.coords and (" |cFF88DDFF(" .. enderData.coords .. ")|r") or ""
        local mapIcon  = ""
        btn.fs:SetText("|cFFFFD200Ends:|r   " .. nameStr .. zoneStr .. coordStr .. mapIcon)
        btn:Show()
        yOff = yOff - 18
    else
        AQ.EnderBtn:Hide()
    end

    yOff = yOff - 6   -- small gap before rewards

    -- Hide all icon slots to start
    for _, icon in ipairs(AQ.RewardIcons) do
        icon:Hide()
        icon.itemData = nil
        icon.isChoice = false
    end
    AQ.RewardLabel:Hide()
    AQ.ChoiceLabel:Hide()
    AQ.GuaranteedLabel:Hide()
    AQ.RewardMoneyText:Hide()

    if rewardsData and AQ_HasRealRewards(rewardsData) then
        -- "Rewards" header
        AQ.RewardLabel:ClearAllPoints()
        AQ.RewardLabel:SetPoint("TOPLEFT", AQ.DetailsFrame, "TOPLEFT", 10, yOff)
        AQ.RewardLabel:SetText("|cFFFFD200Rewards|r")
        AQ.RewardLabel:Show()
        yOff = yOff - 14

        -- XP, money, rep first
        local parts = {}
        if type(rewardsData.xp) == "number" and rewardsData.xp > 0 then
            table.insert(parts, "|cFF8080FF" .. rewardsData.xp .. " XP|r")
        end
        if type(rewardsData.money) == "number" and rewardsData.money > 0 then
            local g = math.floor(rewardsData.money / 10000)
            local s = math.floor((rewardsData.money % 10000) / 100)
            local c = rewardsData.money % 100
            if g > 0 then table.insert(parts, "|cFFFFD700" .. g .. "g|r") end
            if s > 0 then table.insert(parts, "|cFFC0C0C0" .. s .. "s|r") end
            if c > 0 then table.insert(parts, "|cFFCD7F32" .. c .. "c|r") end
        end
        if type(rewardsData.rep) == "table" then
            for _, entry in ipairs(rewardsData.rep) do
                if type(entry) == "table" and entry[1] and entry[2] then
                    table.insert(parts, "|cFF00FF00+" .. entry[2] .. " " .. entry[1] .. " rep|r")
                end
            end
        end
        if #parts > 0 then
            AQ.RewardMoneyText:ClearAllPoints()
            AQ.RewardMoneyText:SetPoint("TOPLEFT", AQ.DetailsFrame, "TOPLEFT", 10, yOff)
            AQ.RewardMoneyText:SetText(table.concat(parts, "  "))
            AQ.RewardMoneyText:Show()
            yOff = yOff - 14
        end

        local iconSlot = 1

        -- Choice rewards (pick one) -- shown after XP/money/rep
        local hasChoice = type(rewardsData.choice) == "table" and #rewardsData.choice > 0
        if hasChoice then
            AQ.ChoiceLabel:ClearAllPoints()
            AQ.ChoiceLabel:SetPoint("TOPLEFT", AQ.DetailsFrame, "TOPLEFT", 10, yOff)
            AQ.ChoiceLabel:SetText("|cFF888888Choose one of the following:|r")
            AQ.ChoiceLabel:Show()
            yOff = yOff - 16

            for idx, itemId in ipairs(rewardsData.choice) do
                if iconSlot <= #AQ.RewardIcons then
                    local icon = AQ.RewardIcons[iconSlot]
                    local xPos = 10 + (idx - 1) * (ICON_SIZE + 4)
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", AQ.DetailsFrame, "TOPLEFT", xPos, yOff)
                    icon.itemId = itemId
                    icon.isChoice = true
                    local _, _, quality, _, _, _, _, _, _, iconPath = GetItemInfo(itemId)
                    icon.tex:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
                    icon:Show()
                    iconSlot = iconSlot + 1
                end
            end
            yOff = yOff - ICON_SIZE - 4
        end

        -- Guaranteed item rewards
        local hasItems = type(rewardsData.items) == "table" and #rewardsData.items > 0
        if hasItems then
            AQ.GuaranteedLabel:ClearAllPoints()
            AQ.GuaranteedLabel:SetPoint("TOPLEFT", AQ.DetailsFrame, "TOPLEFT", 10, yOff)
            AQ.GuaranteedLabel:SetText("|cFF888888You will also receive:|r")
            AQ.GuaranteedLabel:Show()
            yOff = yOff - 16

            for idx, itemId in ipairs(rewardsData.items) do
                if iconSlot <= #AQ.RewardIcons then
                    local icon = AQ.RewardIcons[iconSlot]
                    local xPos = 10 + (idx - 1) * (ICON_SIZE + 4)
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", AQ.DetailsFrame, "TOPLEFT", xPos, yOff)
                    icon.itemId = itemId
                    icon.isChoice = false
                    local _, _, quality, _, _, _, _, _, _, iconPath = GetItemInfo(itemId)
                    icon.tex:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
                    icon:Show()
                    iconSlot = iconSlot + 1
                end
            end
            yOff = yOff - ICON_SIZE - 4
        end
    end

    -- Persistent icon texture loader: keeps polling GetItemInfo via
    -- OnUpdate until every visible reward icon has a real texture.
    -- Unlike timer snapshots, this approach works regardless of server
    -- response time and handles icons that were hidden when data arrived.
    -- It stops itself automatically once all icons are resolved.
    do
        -- Collect item IDs that still need loading
        local pendingIds = {}
        for _, icon in ipairs(AQ.RewardIcons) do
            if icon:IsShown() and icon.itemId then
                local _, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(icon.itemId)
                if not iconPath then
                    pendingIds[icon.itemId] = true
                end
            end
        end

        if next(pendingIds) then
            -- Reuse or create a loader frame
            if not AQ.IconLoader then
                AQ.IconLoader = CreateFrame("Frame")
            end
            AQ.IconLoader.elapsed = 0
            AQ.IconLoader:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed
                -- Check every 0.1s to avoid running every frame
                if self.elapsed < 0.1 then return end
                self.elapsed = 0

                local allDone = true
                for _, icon in ipairs(AQ.RewardIcons) do
                    if icon.itemId and pendingIds[icon.itemId] then
                        local _, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(icon.itemId)
                        if iconPath then
                            icon.tex:SetTexture(iconPath)
                            pendingIds[icon.itemId] = nil
                        else
                            -- GetItemInfo still nil -- force-load via
                            -- SetHyperlink, same as hovering does.
                            if GameTooltip then
                                GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                                GameTooltip:SetHyperlink("item:" .. icon.itemId .. ":0:0:0:0:0:0:0")
                                GameTooltip:Hide()
                            end
                            allDone = false
                        end
                    end
                end

                if allDone then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- Resize the details frame to exactly fit its content so text never
    -- overflows the bottom edge. yOff is negative (distance from top),
    -- so content height = -yOff. Add 16px bottom padding.
    local contentHeight = math.max(100, -yOff + 16)
    AQ.DetailsFrame:SetHeight(contentHeight)

    -- Chain popup: opened/rebuilt only when a quest is selected from the
    -- main dungeon list. When navigating within the chain popup itself,
    -- AQ.suppressChainRebuild is set true so this block is skipped and
    -- the popup stays exactly as it was (static). The suppressChainRebuild
    -- flag is always cleared after this check so it only applies once.
    if not AQ.suppressChainRebuild then
        if hasChain then
            AQ.ShowQuestChain(AQ.CurrentQuest)
        elseif AQ.ChainPopup then
            AQ.ChainPopup:Hide()
        end
    end
    AQ.suppressChainRebuild = nil
    AQ.DetailsFrame:Show()
end

function AQ.ShowQuestDetails(quest)
    AQ.CurrentQuest = quest

    local headerLines = { "|cFFFFD200Quest #" .. quest.id .. "|r" }

    local starterData = nil
    local enderData   = nil
    local hasChain    = false

    if not QuestieLoader then
        table.insert(headerLines, "|cFFFF0000No QuestieLoader found.|r")
        AQ_RenderDetails(table.concat(headerLines, "\n"), starterData, enderData, nil, false)
        return
    end

    local QuestieDB = AQ_GetQuestieDB()
    if not QuestieDB then
        table.insert(headerLines, "|cFFFF0000QuestieDB module could not be imported.|r")
        AQ_RenderDetails(table.concat(headerLines, "\n"), starterData, enderData, nil, false)
        return
    end

    local q, method = AQ_GetQuestieQuest(QuestieDB, quest.id)
    if not q then
        headerLines[1] = "|cFFFFD200Quest #" .. quest.id .. "|r"
        table.insert(headerLines, "|cFFFF0000Quest not found in Questie (" .. tostring(method) .. ").|r")
        AQ_RenderDetails(table.concat(headerLines, "\n"), starterData, enderData, nil, false)
        return
    end

    local questName = q.name or ("Quest #" .. quest.id)
    local isCompleted = AQ_IsQuestCompleted(quest.id)
    local isInLog     = AQ_IsQuestInLog(quest.id)

    if isCompleted then
        headerLines[1] = "|cFFFFD200" .. questName .. "|r"
        table.insert(headerLines, "|cFF00CC00Completed|r")
    elseif isInLog then
        headerLines[1] = "|cFF6699FF" .. questName .. "|r"
        table.insert(headerLines, "|cFF6699FFIn your quest log|r")
    else
        headerLines[1] = "|cFFFFD200" .. questName .. "|r"
    end

    -- ── Starter: NPC, object, or item — entirely from Questie's own
    -- startedBy data, no curated per-quest lookups needed. Questie
    -- stores startedBy as {creatureIds, objectIds, itemIds}, so we try
    -- creature first (the common case), then object (e.g. a chest or
    -- body you interact with), then item (e.g. a journal you loot off
    -- a body and then use to start the quest). The item case reads the
    -- exact same "Sources" data Questie's own Items panel uses for its
    -- "Show on Map" button, and the object case reads the same spawn
    -- data used for object "Show on Map" -- so the pin always matches
    -- what Questie itself would show, and can never go stale.
    local startedByTbl = q.startedBy or q.StartedBy

    local starterId  = AQ_FirstSubId(startedByTbl, 1)
    local starterNpc = AQ_GetNpc(QuestieDB, starterId)
    local starterCoords, starterZone, starterX, starterY = AQ_GetNpcZoneCoords(QuestieDB, starterNpc)
    local starterName = starterNpc and (starterNpc.name or starterNpc.Name)

    if not starterCoords then
        local starterObjectId = AQ_FirstSubId(startedByTbl, 2)
        if starterObjectId then
            local oCoords, oZone, oX, oY = AQ_GetObjectZoneCoords(QuestieDB, starterObjectId)
            if oCoords then
                starterCoords, starterZone, starterX, starterY = oCoords, oZone, oX, oY
                starterName = AQ_GetObjectName(QuestieDB, starterObjectId) or starterName
            end
        end
    end

    if not starterCoords then
        local starterItemId = AQ_FirstSubId(startedByTbl, 3)
        if starterItemId then
            local iCoords, iZone, iX, iY = AQ_GetItemZoneCoords(QuestieDB, starterItemId)
            if iCoords then
                starterCoords, starterZone, starterX, starterY = iCoords, iZone, iX, iY
                starterName = AQ_GetItemName(QuestieDB, starterItemId) or starterName
            end
        end
    end

    -- ── Ender NPC ──────────────────────────────────────────────────
    local enderId  = AQ_FirstNpcId(q.finishedBy or q.FinishedBy)
    local enderNpc = AQ_GetNpc(QuestieDB, enderId)
    local enderCoords, enderZone, enderX, enderY = AQ_GetNpcZoneCoords(QuestieDB, enderNpc)

    local questZone = starterZone or enderZone
    if questZone then
        table.insert(headerLines, "|cFFFFD200Zone:|r " .. questZone)
    end

    -- Faction: derived live from the quest's race requirement (falling
    -- back to the starter NPC's faction) — never hardcoded per-quest.
    local faction = AQ_GetQuestFaction(QuestieDB, q, starterNpc)
    if faction == "A" then
        table.insert(headerLines, "|cFFFFD200Faction:|r |cFF3399FFAlliance|r")
    elseif faction == "H" then
        table.insert(headerLines, "|cFFFFD200Faction:|r |cFFFF3333Horde|r")
    end

    -- Levels
    local reqLevel   = q.requiredLevel or q.RequiredLevel
    local questLevel = q.questLevel or q.level or q.Level
    if reqLevel   and reqLevel   > 0 then table.insert(headerLines, "|cFFFFD200Required Level:|r " .. reqLevel)  end
    if questLevel and questLevel > 0 then table.insert(headerLines, "|cFFFFD200Quest Level:|r "    .. questLevel) end

    -- Objectives / description
    local desc = AQ_ExtractDescription(q)
    if desc then
        table.insert(headerLines, " ")
        table.insert(headerLines, "|cFFFFD200Objectives:|r")
        table.insert(headerLines, desc)
    end

    -- Chain prerequisite / follow-up. Neither the "Pre-quest(s)" nor
    -- "Leads to" text lines are shown in this panel anymore per user
    -- request -- the chain popup, which now opens automatically, already
    -- shows the full chain clearly. We still need to detect
    -- preQuest/nextQuest here to compute hasChain below.
    local preQuest  = q.preQuestSingle  or q.PreQuestSingle
    local nextQuest = q.nextQuestInChain or q.NextQuestInChain
    hasChain = (type(preQuest) == "table" and #preQuest > 0)
            or (type(nextQuest) == "number" and nextQuest > 0)

    starterData = {
        name   = starterName,
        coords = starterCoords,
        zone   = starterZone,
        x      = starterX,
        y      = starterY,
    }
    enderData = {
        name   = enderNpc and (enderNpc.name or enderNpc.Name),
        coords = enderCoords,
        zone   = enderZone,
        x      = enderX,
        y      = enderY,
    }
    -- Don't show a starter/ender box at all if Questie gave us nothing
    -- (no fabricated placeholder data).
    if not (starterData.name or starterData.coords) then starterData = nil end
    if not (enderData.name or enderData.coords) then enderData = nil end

    -- Look up curated reward data for this quest (populated in
    -- AtlasQuestie_Quests.lua). Only dungeon-list quests have entries;
    -- chain quests that have no entry simply get nil (no rewards shown).
    local rewards = AQ.QuestRewards and AQ.QuestRewards[quest.id]

    AQ_RenderDetails(
        table.concat(headerLines, "\n"),
        starterData,
        enderData,
        rewards,
        hasChain
    )
end

-- ============================================================
-- Quest chain popup
-- ============================================================

function AQ.ShowQuestChain(quest)
    local QuestieDB = AQ_GetQuestieDB()
    if not QuestieDB then return end

    local q = AQ_GetQuestieQuest(QuestieDB, quest.id)
    if not q then
        print("|cFFFF0000AtlasQuestie: could not load chain data.|r")
        return
    end

    local preQuest  = q.preQuestSingle  or q.PreQuestSingle
    local nextQuest = q.nextQuestInChain or q.NextQuestInChain
    if not ((type(preQuest) == "table" and #preQuest > 0) or
            (type(nextQuest) == "number" and nextQuest > 0)) then
        print("|cFFFFD200AtlasQuestie:|r This quest has no chain.")
        return
    end

    -- Walk backward from this quest, following preQuestSingle one step
    -- at a time, to find the full chain of prerequisites (not just the
    -- immediate one) -- e.g. BFD's "In Search of Thaelrid" -> "Blackfathom
    -- Villainy". Capped to guard against malformed/circular chain data.
    local beforeIds = {}
    do
        local seen = { [quest.id] = true }
        local currentId = quest.id
        for _ = 1, 20 do
            local curQ = AQ_GetQuestieQuest(QuestieDB, currentId)
            local pre = curQ and (curQ.preQuestSingle or curQ.PreQuestSingle)
            local preId = type(pre) == "table" and pre[1]
            if not (type(preId) == "number" and preId > 0) then break end
            if seen[preId] then break end -- circular reference guard
            seen[preId] = true
            table.insert(beforeIds, 1, preId) -- prepend so earliest ends up first
            currentId = preId
        end
    end

    -- Walk forward the same way, following nextQuestInChain.
    local afterIds = {}
    do
        local seen = { [quest.id] = true }
        local currentId = quest.id
        for _ = 1, 20 do
            local curQ = AQ_GetQuestieQuest(QuestieDB, currentId)
            local nxt = curQ and (curQ.nextQuestInChain or curQ.NextQuestInChain)
            if not (type(nxt) == "number" and nxt > 0) then break end
            if seen[nxt] then break end
            seen[nxt] = true
            table.insert(afterIds, nxt)
            currentId = nxt
        end
    end

    -- Full ordered list of quest IDs in the chain, including this one.
    local chainIds = {}
    for _, id in ipairs(beforeIds) do table.insert(chainIds, id) end
    table.insert(chainIds, quest.id)
    for _, id in ipairs(afterIds) do table.insert(chainIds, id) end

    -- (Re)build the popup frame, sized to fit the number of rows.
    local rowHeight = 23
    local headerHeight = 32
    local popupWidth = 254
    local popupHeight = headerHeight + rowHeight * #chainIds + 14

    if not AQ.ChainPopup then
        AQ.ChainPopup = AQ_CreatePopupFrame("AtlasQuestieChainPopup", AtlasFrame, popupWidth, popupHeight, "Quest Chain")
        -- Anchor to the left of the details panel, set once at creation.
        -- Both frames are now AtlasFrame children so this is stable.
        AQ.ChainPopup:ClearAllPoints()
        if AQ.DetailsFrame then
            AQ.ChainPopup:SetPoint("TOPRIGHT", AQ.DetailsFrame, "TOPLEFT", -4, 0)
        else
            AQ.ChainPopup:SetPoint("CENTER")
        end
    else
        AQ.ChainPopup:SetHeight(popupHeight)
    end
    local popup = AQ.ChainPopup

    -- Clear any rows built for a previous chain.
    if popup.rows then
        for _, row in ipairs(popup.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    popup.rows = {}

    for i, id in ipairs(chainIds) do
        local rowQ = AQ_GetQuestieQuest(QuestieDB, id)
        local label = (rowQ and rowQ.name) or ("Quest #" .. id)
        -- isDungeonQuest: this row is the quest from the main dungeon list
        -- that originally opened the chain. Static -- doesn't change when
        -- you navigate to other chain quests. Tracked via AQ.DungeonAnchorQuestId.
        local isDungeonQuest = (id == (AQ.DungeonAnchorQuestId or quest.id))
        local isInLog = AQ_IsQuestInLog(id)

        local row = CreateFrame("Button", nil, popup)
        row:SetSize(popupWidth - 30, rowHeight)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -headerHeight - rowHeight * (i - 1))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

        -- Selection glow: shown on whichever row is currently displayed
        -- in the Quest Details panel. Same solid-color technique as the
        -- main quest list (no external texture file path to guess at).
        local glow = row:CreateTexture(nil, "BACKGROUND")
        glow:SetAllPoints(row)
        glow:SetTexture(1, 0.82, 0, 0.18)
        glow:Hide()
        row.glow = glow

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", row, "LEFT", 2, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        local numberPrefix = i .. ". "
        -- [dungeon quest] only ever shown on the quest from the main list
        -- (AQ.DungeonAnchorQuestId). It's static -- doesn't move when
        -- you click other rows and navigate to their details.
        local suffix = isDungeonQuest and " |cFFAAAAAA[dungeon quest]|r" or ""

        if AQ_IsQuestCompleted(id) then
            fs:SetText("|cFF00CC00[Done]|r " .. numberPrefix .. "|cFF888888" .. label .. "|r" .. suffix)
        elseif isInLog then
            fs:SetText("|cFF6699FF" .. numberPrefix .. label .. "|r" .. suffix)
        else
            fs:SetText("|cFFFFFFFF" .. numberPrefix .. label .. "|r" .. suffix)
        end

        -- Show glow for whichever quest is currently shown in details.
        if AQ.SelectedChainQuestId == id then
            glow:Show()
        end

        row:SetScript("OnClick", function()
            -- Update the selected-chain glow instantly on all rows.
            AQ.SelectedChainQuestId = id
            for _, r in ipairs(popup.rows or {}) do
                if r.chainQuestId == id then
                    r.glow:Show()
                else
                    r.glow:Hide()
                end
            end
            -- Suppress chain popup rebuild so the popup stays static
            -- while navigating within it -- only the details panel changes.
            AQ.suppressChainRebuild = true
            AQ.ShowQuestDetails({ id = id })
        end)

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine("Left click to view quest details", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.chainQuestId = id
        table.insert(popup.rows, row)
    end

    popup:Show()
end

-- ============================================================
-- Bootstrap
-- ============================================================

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_QUERY_COMPLETE")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local lastCompletedQuery = 0
f:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" and a1 == addonName then
        AQ.OnLoad()
    elseif event == "PLAYER_LOGIN" then
        -- Default the faction filter to the player's own faction on
        -- first run. UnitFactionGroup only returns correct results from
        -- PLAYER_LOGIN onward (not safe to call at ADDON_LOADED time),
        -- so this has to happen here rather than in AQ.OnLoad.
        if not AtlasQuestieDB.factionFilter then
            local englishFaction = UnitFactionGroup and UnitFactionGroup("player")
            if englishFaction == "Alliance" then
                AtlasQuestieDB.factionFilter = "A"
            elseif englishFaction == "Horde" then
                AtlasQuestieDB.factionFilter = "H"
            end
        end
        if AQ.UpdateFactionButtons then AQ.UpdateFactionButtons() end

        -- Force-load all reward item data at login using SetHyperlink on
        -- a hidden tooltip. On this 3.3.5 client GetItemInfo alone does
        -- not reliably trigger a server request, but SetHyperlink does --
        -- it is the same call that happens when you hover an item, which
        -- is why hovering "fixed" the icons. We do it silently here by
        -- using ANCHOR_NONE and immediately hiding the tooltip so nothing
        -- is visible to the player.
        if AQ.QuestRewards and GameTooltip then
            C_Timer.After(1, function()
                -- Small delay so the tooltip system is fully ready
                -- before we start hammering it with requests.
                for _, rewardData in pairs(AQ.QuestRewards) do
                    local function loadItem(itemId)
                        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                        GameTooltip:SetHyperlink("item:" .. itemId .. ":0:0:0:0:0:0:0")
                        GameTooltip:Hide()
                    end
                    if type(rewardData.choice) == "table" then
                        for _, itemId in ipairs(rewardData.choice) do
                            loadItem(itemId)
                        end
                    end
                    if type(rewardData.items) == "table" then
                        for _, itemId in ipairs(rewardData.items) do
                            loadItem(itemId)
                        end
                    end
                end
            end)
        end

        -- Questie's database compiles asynchronously and may not be ready
        -- yet at ADDON_LOADED time. By PLAYER_LOGIN it normally is, so
        -- rebuild the quest list now to replace any placeholder rows.
        if AQ.QuestListContent then
            AQ_BuildQuestList()
        end
        -- Ask the server for the completed-quest list. The response
        -- arrives asynchronously via QUEST_QUERY_COMPLETE below (required
        -- pre-patch-5.0.4 -- GetQuestsCompleted() returns nothing useful
        -- until this has been requested at least once this session).
        if QueryQuestsCompleted then
            QueryQuestsCompleted()
            lastCompletedQuery = GetTime()
        end
    elseif event == "QUEST_QUERY_COMPLETE" then
        AQ_RefreshCompletedQuests()
        if AQ.QuestListContent then
            AQ_BuildQuestList()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        -- QUEST_LOG_UPDATE fires very often (zone changes, picking up
        -- items, etc.), not just on quest completion, and the docs warn
        -- QueryQuestsCompleted() is rate-limited server-side -- so only
        -- re-query at most once every few seconds rather than on every
        -- single firing.
        if QueryQuestsCompleted and (GetTime() - lastCompletedQuery) > 3 then
            lastCompletedQuery = GetTime()
            QueryQuestsCompleted()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- a1 = itemId, a2 = success. Refresh any visible reward icon
        -- that was showing a placeholder ? because this item wasn't in
        -- the local cache when the quest details were first rendered.
        local receivedId = tonumber(a1)
        if receivedId and AQ.RewardIcons then
            for _, icon in ipairs(AQ.RewardIcons) do
                if icon:IsShown() and icon.itemId == receivedId then
                    local _, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(receivedId)
                    if iconPath then
                        icon.tex:SetTexture(iconPath)
                    end
                end
            end
        end
    end
end)

SLASH_AQ1 = "/aq"
SlashCmdList["AQ"] = function(m)
    if m == "toggle" then
        AtlasQuestieDB.enabled = not AtlasQuestieDB.enabled
        print("AtlasQuestie " .. (AtlasQuestieDB.enabled and "ON" or "OFF"))
        return
    end

    local debugNpcId = m:match("^debug npc (%d+)$")
    if debugNpcId then
        local QuestieDB = AQ_GetQuestieDB()
        if not QuestieDB then
            print("|cFFFF0000AtlasQuestie:|r QuestieDB not available.")
            return
        end
        local npc = AQ_GetNpc(QuestieDB, tonumber(debugNpcId))
        if not npc then
            print("|cFFFF0000AtlasQuestie:|r no NPC found for id " .. debugNpcId)
            return
        end
        print("|cFFFFD200AtlasQuestie debug - NPC " .. debugNpcId .. "|r")
        print("  name = " .. tostring(npc.name or npc.Name))
        for k, v in pairs(npc) do
            if k == "spawns" or k == "Spawns" then
                print("  " .. k .. " (table):")
                for zk, zv in pairs(v) do
                    local zvType = type(zv)
                    local sample = ""
                    if zvType == "table" and zv[1] then
                        local p = zv[1]
                        if type(p) == "table" then
                            sample = " e.g. point[1] = {" .. table.concat((function()
                                local parts = {}
                                for i = 1, #p do parts[i] = tostring(p[i]) end
                                return parts
                            end)(), ", ") .. "}"
                        end
                    end
                    print("    [" .. tostring(zk) .. "] (" .. tostring(zk) .. ":" .. type(zk) .. ") = " .. zvType .. sample)
                end
            elseif type(v) ~= "table" then
                print("  " .. tostring(k) .. " = " .. tostring(v))
            else
                print("  " .. tostring(k) .. " = <table>")
            end
        end

        -- Show exactly what our zone-name resolution produces for this
        -- NPC's zoneID, and whether that name is actually findable on
        -- the live world map -- the two places this has been breaking.
        local flatZoneId = npc.zoneID or npc.ZoneID
        if flatZoneId then
            local resolvedName = AQ_ZoneIdToName(flatZoneId)
            print("  AQ_ZoneIdToName(" .. tostring(flatZoneId) .. ") = " .. tostring(resolvedName))
            if resolvedName then
                local cN, zN, isSub = AQ_FindZoneIndices(resolvedName)
                if cN then
                    print("  -> found on map: continent " .. cN .. ", zone " .. zN .. (isSub and " (via subzone match)" or ""))
                else
                    print("  -> |cFFFF0000NOT found in GetMapZones/GetMapSubzones with this name.|r")
                end
            else
                print("  -> |cFFFF0000zoneID not found in ZoneDB.zoneIDs; no name to search with.|r")
            end
        end
        return
    end

    -- /aq debug zone <questieZoneId>: empirically tests whether
    -- GetMapNameByID resolves a Questie zoneID directly (AreaID and
    -- WorldMapAreaID are documented as separate systems, but may
    -- coincide on the 3.3.5 client -- testing in-game is more reliable
    -- than reasoning about it from outside).
    local debugZoneId = m:match("^debug zone (%d+)$")
    if debugZoneId then
        local id = tonumber(debugZoneId)
        print("|cFFFFD200AtlasQuestie debug - zone " .. debugZoneId .. "|r")
        if GetMapNameByID then
            local ok, name = pcall(GetMapNameByID, id)
            print("  GetMapNameByID(" .. debugZoneId .. ") = " .. tostring(ok and name or "<error>"))
        else
            print("  GetMapNameByID not available on this client.")
        end
        return
    end

    -- /aq debug maplist: dumps every continent/zone/subzone name the
    -- client knows about (this client returns NAMES ONLY, no numeric
    -- IDs -- confirmed by testing), so we can visually find the
    -- position/index of a given zone without guessing.
    if m == "debug maplist" then
        if not (GetMapContinents and GetMapZones) then
            print("|cFFFF0000AtlasQuestie:|r map API not available.")
            return
        end
        local continentNames = { GetMapContinents() }
        for continentN = 1, #continentNames do
            print("|cFFFFD200Continent " .. continentN .. ": " .. tostring(continentNames[continentN]) .. "|r")
            local zoneNames = { GetMapZones(continentN) }
            for zoneN = 1, #zoneNames do
                print("  zone[" .. zoneN .. "] = " .. tostring(zoneNames[zoneN]))
                if GetMapSubzones then
                    local ok, subzones = pcall(function() return { GetMapSubzones(zoneNames[zoneN]) } end)
                    if ok and subzones and #subzones > 0 then
                        for i, v in ipairs(subzones) do
                            print("    sub[" .. i .. "] = " .. tostring(v))
                        end
                    end
                end
            end
        end
        return
    end
end
