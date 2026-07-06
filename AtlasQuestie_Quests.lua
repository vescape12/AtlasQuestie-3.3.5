local addonName, AQ = ...

-- ============================================================
-- AtlasQuestie_Quests.lua
--
-- This is the ONLY file you should need to edit to add/update
-- dungeons, quests, or rewards. Everything else (name, faction,
-- NPC, coords) is fetched live from Questie at display time.
--
-- FORMAT
-- ------
-- Each dungeon is a list that mixes quest IDs with their reward table
--
--   RagefireChasm = {
--       14356, -- The Power to Destroy...
--       { xp = 1750, rep = { { "Undercity", 500 } }, choice = { 15449, 15450, 15451 } },
--
--       5730, -- Hidden Enemies
--       { xp = 1450, rep = { { "Orgrimmar", 350 } }, choice = { 15443, 15445, 15424, 15444 } },
--   },
--
--
-- Reward table fields (all optional):
--   xp     = number          (XP awarded)
--   money  = number          (copper: 100 = 1s, 10000 = 1g)
--   rep    = { {factionName, amount}, ... }
--   choice = { itemId, ... } (pick ONE of these items)
--   items  = { itemId, ... } (you receive ALL of these)
--
-- Items are stored as numeric IDs only -- the game client supplies
-- full tooltip stats (including shift-compare) automatically via
-- GameTooltip:SetHyperlink.
--
-- To add a new dungeon: add its name and questID below with its
-- rewards list. Item IDs verified against Wowhead/Wowpedia. XP
-- values are WotLK 3.3.5 amounts.
-- ============================================================

AQ.Dungeons = {
    RagefireChasm = {
        14356, -- The Power to Destroy...
        { xp = 1750, rep = { { "Undercity", 500 } }, choice = { 15449, 15450, 15451 } },

        5730, -- Hidden Enemies
        { xp = 1450, rep = { { "Orgrimmar", 350 } }, choice = { 15443, 15445, 15424, 15444 } },

        5723, -- Testing an Enemy's Strength
        { xp = 1600, money = 700, rep = { { "Thunder Bluff", 500 } } },

        5724, -- Returning the Lost Satchel
        { xp = 1750, rep = { { "Thunder Bluff", 500 } }, choice = { 15452, 15453 } },

        5761, -- Slaying the Beast
        { xp = 1750, money = 800 },
    },

    TheDeadmines = {
        166, -- The Defias Brotherhood
        { xp = 2600, rep = { { "Stormwind", 250 } }, choice = { 6087, 2041, 2042 } },

        214, -- Red Silk Bandanas
        { xp = 1900, rep = { { "Stormwind", 500 } }, choice = { 2074, 2089, 6094 } },

        167, -- Oh Brother...
        { xp = 1550, rep = { { "Ironforge", 250 } }, items = { 1893 } },

        168, -- Collecting Memories
        { xp = 1350, rep = { { "Ironforge", 250 } }, choice = { 2037, 2036 } },

        2040, -- Underground Assault
        { xp = 2350, rep = { { "Stormwind", 500 }, { "Gnomeregan Exiles", 500 } }, choice = { 7606, 7607 } },
    },

    WailingCaverns = {
        914, -- Leaders of the Fang
        { xp = 2600, choice = { 6505, 6504 } },

        959, -- Trouble at the Docks
        { xp = 1350, money = 1000, rep = { { "Ratchet", 250 } } },

        1487, -- Deviate Eradication
        { xp = 2500, money = 2500, choice = { 6476, 8071, 6481 } },

        1486, -- Deviate Hides
        { xp = 1900, money = 1800, choice = { 6480, 918 } },

        1491, -- Smart Drinks
        { xp = 2050, money = 1000, rep = { { "Ratchet", 500 } } },

        962, -- Serpentbloom
        { xp = 1350, money = 1000, items = { 10919 }, rep = { { "Undercity", 250 } } },

        3369, -- In Nightmares, Horde
        { xp = 2000, rep = { { "Thunder Bluff", 250 } }, choice = { 10657, 10658 } },

        3370, -- In Nightmares, Alliance
        { xp = 2000, rep = { { "Darnassus", 250 } }, choice = { 10657, 10658 } },
    },

        ShadowfangKeep = {
        1013, -- The Book of Ur
        { xp = 3150, rep = { { "Undercity", 500 } }, choice = { 6335, 4534 } },
       
        1014, -- Arugal Must Die
        { xp = 3300, rep = { { "Undercity", 500 } }, items = { 6414 } },
       
        1098, -- Deathstalkers in Shadowfang
        { xp = 3050, rep = { { "Undercity", 500 } }, money = 1800, items = { 3324 } },
    },

        BlackfathomDeeps = {
        6561, -- Blackfathom Villainy, Horde
        { xp = 3300, rep = { { "Argent Dawn", 500 }, { "Thunder Bluff", 500 } }, money = 6500, choice = { 7001, 7002 } },
   
        6563, -- The Essence of Aku'Mai
        { xp = 1750, rep = { { "Darkspear Trolls", 250 } }, money = 1400 },
   
        6565, -- Allegiance to the Old Gods, part 2 of 2
        { xp = 3150, rep = { { "Darkspear Trolls", 500 } }, money = 4000, choice = { 17694, 17695 } },
        
        6921, -- Amongst the Ruins
        { xp = 3300, rep = { { "Darkspear Trolls", 500 } }, money = 4500 },
        
        6922, -- Baron Aquanis
        { xp = 3650, rep = { { "Darkspear Trolls", 500 } }, choice = { 16886, 16887 } },
        
        971, -- Knowledge in the Deeps
        { xp = 2750, rep = { { "Ironforge", 75 } }, items = { 6743 } },
        
        1199, -- Twilight Falls
        { xp = 3050, rep = { { "Argent Dawn", 500 }, { "Darnassus", 500 } }, items = { 6998, 7000 } },
        
        1200, -- Blackfathom Villainy, Alliance
        { xp = 3300, rep = { { "Argent Dawn", 500 }, { "Darnassus", 500 } }, money = 6500, choice = { 7001, 7002 } },
        
        1275, -- Researching the Corruption
        { xp = 2900, rep = { { "Darnassus", 250 } }, money = 3500, choice = { 7003, 7004 } },
    },

    TheStockade = {
        378, -- The Fury Runs Deep
        { xp = 3300, rep = { { "Ironforge", 500 } }, choice = { 3562, 1264 } },

        377, -- Crime and Punishment
        { xp = 3150, rep = { { "Stormwind", 500 } }, choice = { 2033, 2906 } },

        386, -- What Comes Around...
        { xp = 3050, rep = { { "Stormwind", 500 } }, choice = { 3400, 1317 } },

        388, -- The Color of Blood
        { xp = 3150, rep = { { "Stormwind", 500 } }, money = 6000 },

        391, -- The Stockade Riots
        { xp = 3550, rep = { { "Stormwind", 500 } }, money = 2500 },

        387, -- Quell The Uprising
        { xp = 3150, rep = { { "Stormwind", 500 } }, money = 6000 },
    },

    Gnomeregan = {
        2924, -- Essential Artificials
        2930, -- Data Rescue
        2926, -- Gnogaine
        2928, -- Gyrodrillmatic Excavationators
        2929, -- The Grand Betrayal
        2922, -- Save Techbot's Brain!
        2841, -- Rig Wars (Horde)
        2904, -- A Fine Mess
        2843, -- Gnomer-gooooone!
        2948, -- Gnome Improvement
        2950, -- Nogg's Ring Redo
        2962, -- The Only Cure is More Green Glow
    },

    RazorfenKraul = {
        1101, -- The Crone of the Kraul (Alliance)
        1102, -- A Vengeful Fate (Horde)
        1142, -- Mortality Wanes (Alliance, inside)
        1109, -- Going, Going, Guano! (Horde)
        1221, -- Blueleaf Tubers (neutral)
        1144, -- Willix the Importer (neutral, escort)
    },

    SMGraveyard = {
        1051, -- Vorrel's Revenge
    },

    SMLibrary = {
        1049, -- Compendium of the Fallen
        1050, -- Mythology of the Titans
        1160, -- Test of Lore
    },

    SMArmory = {
        1053,  -- In the Name of the Light
        14355, -- Into The Scarlet Monastery
    },

    SMCathedral = {
        1113, -- Hearts of Zeal
    },

    RazorfenDowns = {
        3341,  -- Bring the End
        6626,  -- A Host of Evil
        14353, -- An Unholy Alliance
        3525,  -- Extinguishing the Idol
        3636,  -- Bring the Light
    },

    Uldaman = {
        704,  -- Agmond's Fate
        721,  -- A Sign of Hope
        709,  -- Solution to Doom
        2418, -- Power Stones
        2240, -- The Hidden Chamber
        2200, -- Back to Uldaman
        1139, -- The Lost Tablets of Will
        2278, -- The Platinum Discs
        2198, -- The Shattered Necklace
        3375, -- Replacement Phial
        17,   -- Uldaman Reagent Run
    },
}

-- ============================================================
-- Do not edit below this line.
--
-- This expands AQ.Dungeons above into the two tables the rest
-- of the addon actually reads:
--   AQ.DungeonQuestIds[zoneID] = { questId, questId, ... }
--   AQ.QuestRewards[questId]   = { xp = ..., rep = ..., ... }
-- ============================================================

AQ.DungeonQuestIds = {}
AQ.QuestRewards = {}

for zoneID, entries in pairs(AQ.Dungeons) do
    local questIds = {}
    local lastQuestId = nil

    for _, entry in ipairs(entries) do
        if type(entry) == "number" then
            -- A bare number is a quest ID.
            table.insert(questIds, entry)
            lastQuestId = entry
        elseif type(entry) == "table" and lastQuestId then
            -- A table immediately following a quest ID is that
            -- quest's reward data.
            AQ.QuestRewards[lastQuestId] = entry
            lastQuestId = nil
        end
    end

    AQ.DungeonQuestIds[zoneID] = questIds
end
