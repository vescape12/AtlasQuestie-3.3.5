local addonName, AQ = ...

-- ============================================================
-- AtlasQuestie_Quests.lua
--
-- DUNGEON QUEST LIST: keyed by Atlas zoneID string.
-- Stores only quest IDs; all live data (name, faction, NPC,
-- coords) is fetched from Questie at display time.
--
-- QUEST REWARDS: AQ.QuestRewards below.
-- Stores curated reward data for MAIN dungeon quests only
-- (not chain quests). Each entry is keyed by quest ID and
-- may contain:
--   xp     = number          (XP awarded)
--   money  = number          (copper: 100=1s, 10000=1g)
--   rep    = { {factionName, amount}, ... }
--   choice = { itemId, ... } (pick ONE of these items)
--   items  = { itemId, ... } (you receive ALL of these)
--
-- Items are stored as numeric IDs only. The game client
-- supplies full tooltip stats (including shift-compare with
-- equipped gear) automatically via GameTooltip:SetHyperlink.
--
-- To add a new dungeon quest list: add its Atlas zoneID key
-- below in DungeonQuestIds with the quest ID array.
-- To add rewards for a quest: add an entry in QuestRewards
-- keyed by the quest's numeric ID.
-- ============================================================

AQ.DungeonQuestIds = {
    RagefireChasm = {
        14356, -- The Power to Destroy...
        5730,  -- Hidden Enemies
        5723,  -- Testing an Enemy's Strength
        5724,  -- Returning the Lost Satchel
        5761,  -- Slaying the Beast
    },
    TheDeadmines = {
        166,   -- The Defias Brotherhood
        214,   -- Red Silk Bandanas
        167,   -- Oh Brother...
        168,   -- Collecting Memories
        2040,  -- Underground Assault
    },
    WailingCaverns = {
        914,  -- Leaders of the Fang
        959,  -- Trouble at the Docks
        1487, -- Deviate Eradication
        1486, -- Deviate Hides
        1491, -- Smart Drinks
        962,  -- Serpentbloom
        3369, -- In Nightmares, Horde
        3370, -- In Nightmares, Alliance
    },
    ShadowfangKeep = {
        1013, -- The Book of Ur
        1014, -- Arugal Must Die
        1098, -- Deathstalkers in Shadowfang
    },
    BlackfathomDeeps = {
        6561, -- Blackfathom Villainy, Horde
        6563, -- The Essence of Aku'Mai
        6565, -- Allegiance to the Old Gods, part 2 of 2
        6921, -- Amongst the Ruins
        6922, -- Baron Aquanis
        971,  -- Knowledge in the Deeps
        1199, -- Twilight Falls
        1200, -- Blackfathom Villainy, Alliance
        1275, -- Researching the Corruption
    },
    TheStockade = {
        378,  -- The Fury Runs Deep
        377,  -- Crime and Punishment
        386,  -- What Comes Around...
        388,  -- The Color of Blood
        391,  -- The Stockade Riots
        387,  -- Quell The Uprising
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
        1053, -- In the Name of the Light
        14355, -- Into The Scarlet Monastery
    },
    SMCathedral = {
        1113, -- Hearts of Zeal
    },
    RazorfenDowns = {
        3341, -- Bring the End
        6626, -- A Host of Evil
        14353, -- An Unholy Alliance
        3525, -- Extinguishing the Idol
        3636, -- Bring the Light
    },
    Uldaman = {
        704,   -- Agmond's Fate
        721,   -- A Sign of Hope
        709,   -- Solution to Doom
        2418,  -- Power Stones
        2240,  -- The Hidden Chamber
        2200,  -- Back to Uldaman
        1139,  -- The Lost Tablets of Will
        2278,  -- The Platinum Discs
        2198,  -- The Shattered Necklace
        3375,  -- Replacement Phial
        17,    -- Uldaman Reagent Run
    },
}

-- ============================================================
-- Quest Rewards
-- Keyed by quest ID. AQ.QuestRewards entries can hold:
--
--   xp     = number          (XP awarded)
--   money  = number          (copper: 100=1s, 10000=1g)
--   rep    = { {factionName, amount}, ... }
--   choice = { itemId, ... } (pick ONE of these items)
--   items  = { itemId, ... } (you receive ALL of these)
--
-- Quest STARTERS (name/zone/coords/pin) are never curated here -- they
-- are always resolved live from Questie's own startedBy data, which
-- covers all three ways a quest can begin:
--   startedBy[1] -- NPC(s)     (the common case)
--   startedBy[2] -- object(s)  (a chest, a body, etc.)
--   startedBy[3] -- item(s)    (e.g. a journal you loot and then use)
-- This is exactly the data behind Questie's own "Show on Map" buttons
-- on its NPC/Object/Item panels, so the pin can never go stale or
-- disagree with Questie. Only dungeon-list quests that also award
-- something get an entry below; chain quests with no reward of their
-- own simply have no entry and show no Rewards section, while their
-- starter location still resolves correctly.
--
-- Item IDs verified against Wowhead and Wowpedia.
-- All XP values are WotLK 3.3.5 amounts.
-- ============================================================

AQ.QuestRewards = {

    -- ========== Ragefire Chasm ==========

    -- The Power to Destroy... (quest 14356)
    -- Bragor Bloodfist, Undercity. Collect 2 spellbooks from Searing Blade.
    [14356] = {
        xp     = 1750,
        rep    = { { "Undercity", 500 } },
        choice = { 15449, 15450, 15451 },
        -- 15449 Ghastly Trousers   (Cloth legs)
        -- 15450 Dredgemire Leggings (Leather legs)
        -- 15451 Gargoyle Leggings  (Mail legs)
    },

    -- Returning the Lost Satchel (quest 5724)
    -- Rahauro, Thunder Bluff. Find Maur Grimtotem's body in RFC.
    [5724] = {
        xp     = 1750,
        rep    = { { "Thunder Bluff", 500 } },
        choice = { 15452, 15453 },
        -- 15452 Featherbead Bracers (Cloth wrist)
        -- 15453 Savannah Bracers    (Leather wrist)
    },

    -- Hidden Enemies (quest 5730)
    -- Thrall, Orgrimmar. Final step of the Hidden Enemies chain.
    [5730] = {
        xp    = 1450,
        rep   = { { "Orgrimmar", 350 } },
        choice = { 15443, 15445, 15424, 15444 },  -- Kris of Orgrimmar / Hammer of Orgrimmar / Axe of Orgrimmar / Staff of Orgrimmar
    },

    -- Testing an Enemy's Strength (quest 5723)
    -- Rahauro, Thunder Bluff. Kill Ragefire Troggs and Shaman.
    [5723] = {
        xp  = 1600,
        money = 700,
        rep = { { "Thunder Bluff", 500 } },
    },

    -- Slaying the Beast (quest 5761)
    -- Neeru Fireblade, Orgrimmar. Kill Taragaman the Hungerer.
    [5761] = {
        xp    = 1750,
        money = 800,   -- 8 silver
    },

        -- ========== The Deadmines ==========

    -- Red Silk Bandanas
    [214] = {
        xp     = 1900,
        rep    = { { "Stormwind", 500 } },
        choice = { 2074, 2089, 6094 },
    },

    -- Collecting Memories
    [168] = {
        xp     = 1350,
        rep    = { { "Ironforge", 250 } },
        choice = { 2037, 2036 },
    },

    -- Oh Brother. . .
    [167] = {
        xp     = 1550,
        rep    = { { "Ironforge", 250 } },
        item = { 1893 },
    },

    -- Underground Assault
    [2040] = {
        xp     = 2350,
        rep    = { { "Stormwind", "Gnomeregan Exiles", 500 } },
        choice = { 7606, 7607 },
    },

    -- The Defias Brotherhood
    [166] = {
        xp     = 2600,
        rep    = { { "Stormwind", 250 } },
        choice = { 6087, 2041, 2042 },
    },

        -- ========== Wailing Caverns ==========

    -- Leaders of the Fang (quest 914)
    [914] = {
        xp     = 2600,
        choice = { 6505, 6504 },  -- Crescent Staff / Wingblade
    },

    -- Trouble at the Docks (quest 959)
    [959] = {
        xp    = 1350,
        money = 1000,
        rep   = { { "Ratchet", 250 } },
    },

    -- Deviate Eradication (quest 1487)
    [1487] = {
        xp     = 2500,
        money  = 2500,
        choice = { 6476, 8071, 6481 },  -- Pattern: Deviate Scale Belt / Sizzle Stick / Dagmire Gauntlets
    },

    -- Deviate Hides (quest 1486)
    [1486] = {
        xp     = 1900,
        money  = 1800,
        choice = { 6480, 918 },  -- Slick Deviate Leggings / Deviate Hide Pack
    },

    -- Smart Drinks (quest 1491)
    [1491] = {
        xp    = 2050,
        money = 1000,
        rep   = { { "Ratchet", 500 } },
    },

    -- Serpentbloom (quest 962)
    [962] = {
        xp    = 1350,
        money = 1000,
        items = { 10919 },  -- Apothecary Gloves
        rep   = { { "Undercity", 250 } },
    },

    -- In Nightmares, Horde (quest 3369)
    [3369] = {
        xp     = 2000,
        rep    = { { "Thunder Bluff", 250 } },
        choice = { 10657, 10658 },  -- Talbar Mantle / Quagmire Galoshes
    },

    -- In Nightmares, Alliance (quest 3370)
    [3370] = {
        xp     = 2000,
        rep    = { { "Darnassus", 250 } },
        choice = { 10657, 10658 },  -- Talbar Mantle / Quagmire Galoshes
    },

    -- ========== The Stockade ==========

    -- The Fury Runs Deep
    [378] = {
        xp     = 3300,
        rep    = { { "Ironforge", 500 } },
        choice = { 3562, 1264 },
    },

    -- Crime and Punishment
    [377] = {
        xp     = 3150,
        rep    = { { "Stormwind", 500 } },
        choice = { 2033, 2906 },
    },

    -- What Comes Around...
    [386] = {
        xp     = 3050,
        rep    = { { "Stormwind", 500 } },
        choice = { 3400, 1317 },
    },

    -- The Color of Blood
    [388] = {
        xp     = 3150,
        rep    = { { "Stormwind", 500 } },
        money = 6000
    },

    -- The Stockade Riots
    [391] = {
        xp     = 3550,
        rep    = { { "Stormwind", 500 } },
        money = 2500
    },

    -- Quell The Uprising
    [387] = {
        xp     = 3150,
        rep    = { { "Stormwind", 500 } },
        money = 6000
    },

}
