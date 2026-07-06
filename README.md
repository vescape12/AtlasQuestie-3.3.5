# AtlasQuestie

An AtlasQuest-style quest list for the classic **Atlas** addon, powered by **Questie**'s quest/NPC/item database. Shows the quest chain and rewards for whichever dungeon you have open in Atlas — no separate window, no manual lookups.

Built for **3.3.5 (WotLK)**.

## Dependencies

| Addon | Required? |
|---|---|
| [Atlas](https://www.curseforge.com/wow/addons/atlas-classic) | **Required** — AtlasQuestie attaches to Atlas's window and reads its currently selected dungeon. |
| [Questie](https://github.com/Questie/Questie) | **Required** — supplies all quest names, NPCs, and item data. AtlasQuestie has no quest database of its own. |

Load order doesn't matter; AtlasQuestie waits for both to be ready.

## Usage

Open Atlas and select a dungeon as normal — the quest list appears automatically alongside it.

`/aq toggle` — enable/disable AtlasQuestie.

## Adding/updating quest data

All dungeon quest IDs and rewards live in **`AtlasQuestie_Quests.lua`** — it's the only file you should ever need to touch. See the comment block at the top of that file for the format.

## Status

Actively maintained, but still early — expect gaps in dungeon/quest coverage. Bug reports and PRs welcome.
