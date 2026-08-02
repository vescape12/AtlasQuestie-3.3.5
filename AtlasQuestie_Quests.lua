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
        { xp = 3650, money = 5500, rep = { { "Gnomeregan Exiles", 500 } } },
        
        2930, -- Data Rescue
        { xp = 3650, money = 2500, rep = { { "Gnomeregan Exiles", 500 } }, items = { 9605, 9604 } },
        
        2926, -- Gnogaine
        { xp = 3300, money = 2200, rep = { { "Gnomeregan Exiles", 500 } } },
        
        2928, -- Gyrodrillmatic Excavationators
        { xp = 3650, rep = { { "Stormwind", 500 }, { "Gnomeregan Exiles", 500 } }, choice = { 9608, 9609 } },
        
        2929, -- The Grand Betrayal
        { xp = 4950, money = 3500, rep = { { "Gnomeregan Exiles", 500 } }, choice = { 9623, 9624, 9625 } },
        
        2922, -- Save Techbot's Brain!
        { xp = 2650, money = 2000, rep = { { "Gnomeregan Exiles", 350 } } },
        
        2841, -- Rig Wars (Horde)
        { xp = 4950, rep = { { "Orgrimmar", 500 } }, choice = { 9623, 9624, 9625 } },
        
        2904, -- A Fine Mess
        { xp = 3650, choice = { 9535, 9536 } },
        
        2843, -- Gnomer-gooooone!
        { items = { 9173 } },
        
        2948, -- Gnome Improvement
        { xp = 3300, rep = { { "Ironforge", 250 }, { "Gnomeregan Exiles", 250 } }, items = { 9538 } },
        
        2950, -- Nogg's Ring Redo
        { xp = 3300, rep = { { "Orgrimmar", 250 } }, items = { 9588 } },
        
        2962, -- The Only Cure is More Green Glow
        { xp = 3650, money = 2500 },
    },

    RazorfenKraul = {
        1101, -- The Crone of the Kraul (Alliance)
        { xp = 3300, choice = { 4197, 6742, 6725 }, items = { 29200 } },
        
        1102, -- A Vengeful Fate (Horde)
        { xp = 3300, rep = { { "Thunder Bluff", 500 } }, choice = { 4197, 6742, 6725 } },
        
        1142, -- Mortality Wanes (Alliance, inside)
        { xp = 3650, rep = { { "Darnassus", 500 } }, choice = { 6751, 6752 } },
        
        1109, -- Going, Going, Guano! (Horde)
        { xp = 3150, rep = { { "Undercity", 500 } } },
        
        1221, -- Blueleaf Tubers (neutral)
        { xp = 3150, rep = { { "Ratchet", 500 } }, items = { 6755 } },
        
        1144, -- Willix the Importer (neutral, escort)
        { xp = 3650, rep = { { "Ratchet", 500 } }, choice = { 6748, 6750, 6749 } },
    },

    SMGraveyard = {
        1051, -- Vorrel's Revenge
        { xp = 4350, rep = { { "Undercity", 500 } }, choice = { 7750, 4643 }, items = { 7751 } },
    },

    SMLibrary = {
        1049, -- Compendium of the Fallen
        { xp = 5850, rep = { { "Thunder Bluff", 500 } }, choice = { 7747, 17508, 7749 } },
        
        1050, -- Mythology of the Titans
        { xp = 5850, rep = { { "Ironforge", 500 } }, items = { 7746 } },
        
        1160, -- Test of Lore
        { xp = 5250, rep = { { "Undercity", 500 } } },
    },

    SMArmory = {
        1053,  -- In the Name of the Light
        { xp = 6550, rep = { { "Stormwind", 500 } }, choice = { 6829, 6830, 6831, 11262 } },
        
        14355, -- Into The Scarlet Monastery
        { xp = 7200, rep = { { "Undercity", 500 } }, choice = { 6802, 6803, 10711 } },
    },

    SMCathedral = {
        1113, -- Hearts of Zeal
        { xp = 4350, rep = { { "Undercity", 500 } } },
    },

    RazorfenDowns = {
        3341, -- Bring the End
        { xp = 5550, rep = { { "Undercity", 500 } }, items = { 10823, 10824 } },

        6626, -- A Host of Evil
        { xp = 4100, money = 7500 },

        14353, -- An Unholy Alliance
        { xp = 5250, money = 2000, choice = { 17039, 17042, 17043 } },

        3525, -- Extinguishing the Idol
        { xp = 5550, items = { 10710 } },

        3636, -- Bring the Light
        { xp = 5550, rep = { { "Stormwind", 500 } }, items = { 10823, 10824 } },
    },

    Uldaman = {
        709, -- Solution to Doom
        { xp = 4350, items = { 4746 } },

        1139, -- The Lost Tablets of Will
        { xp = 8300, money = 13000, rep = { { "Ironforge", 500 } }, items = { 6723 } },

        2339, -- Find the Gems and Power Source
        { xp = 7900, rep = { { "Darkspear Trolls", 500 } } },

        1360, -- Reclaimed Treasures
        { xp = 5050, money = 6000, rep = { { "Ironforge", 250 } } },

        2341, -- Necklace Recovery, Take 3
        { xp = 7900, rep = { { "Darkspear Trolls", 250 } }, items = { 7888 } },

        2342, -- Reclaimed Treasures
        { xp = 5050, money = 6000, rep = { { "Undercity", 250 } } },

        2418, -- Power Stones
        { xp = 3500, rep = { { "Booty Bay", 250 }, { "Bloodsail Buccaneers", 250 } }, choice = { 9522, 10358, 10359 } },

        2240, -- The Hidden Chamber
        { xp = 6550, rep = { { "Ironforge", 500 } }, choice = { 9626, 9627 } },

        17, -- Uldaman Reagent Run
        { xp = 4800, money = 5500, rep = { { "Ironforge", 250 } }, items = { 9030 } },

        2202, -- Uldaman Reagent Run
        { xp = 4800, money = 5500, rep = { { "Darkspear Trolls", 250 } }, items = { 9030 } },

        704, -- Agmond's Fate
        { xp = 3900, rep = { { "Ironforge", 250 } }, items = { 4980 } },

        2361, -- Restoring the Necklace
        { xp = 7900, rep = { { "Gnomeregan Exiles", 500 } }, items = { 7673 } },

        2439, -- The Platinum Discs
        { xp = 600, choice = { 3928, 6149 }, items = { 9587 } },

        2440, -- The Platinum Discs
        { xp = 600, rep = { { "Thunder Bluff", 10 } }, choice = { 3928, 6149 }, items = { 9587 } },
    },

    Maraudon = {
        7067, -- The Pariah's Instructions
        { xp = 9400, money = 14000, items = { 17774, 17757 } },

        7044, -- Legends of Maraudon
        { xp = 9800 },

        7064, -- Corruption of Earth and Seed
        { xp = 10600, rep = { { "Cenarion Circle", 500 } }, choice = { 17705, 17743, 17753 } },

        7065, -- Corruption of Earth and Seed
        { xp = 10600, rep = { { "Cenarion Circle", 500 } }, choice = { 17705, 17743, 17753 } },

        7028, -- Twisted Evils
        { xp = 9050, choice = { 17775, 17776, 17777, 17779 } },

        7066, -- Seed of Life
        { xp = 10600, money = 15000, rep = { { "Cenarion Circle", 500 } } },

        7046, -- The Scepter of Celebras
        { xp = 8150, items = { 17191 } },

        7070, -- Shadowshard Fragments
        { xp = 7200, rep = { { "Stormwind", 500 } }, choice = { 17772, 17773 } },

        7068, -- Shadowshard Fragments
        { xp = 7200, rep = { { "Darkspear Trolls", 500 } }, choice = { 17772, 17773 } },

        7041, -- Vyletongue Corruption
        { xp = 9050, choice = { 17768, 17778, 17770 } },

        7029, -- Vyletongue Corruption
        { xp = 9050, choice = { 17768, 17778, 17770 } },
},

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
