--!strict
-- Shared helpers for world (server) and personal (client) leaderboard rows.
-- Default row children: Rank (TextLabel), Name (TextLabel), Value (TextLabel), Head (ImageLabel).

export type BoardKind = "Coins" | "EggsHatched" | "Time"

export type RowEntry = {
	rank: number,
	userId: number,
	score: number,
	displayName: string,
}

export type ValueFormat = "raw" | "compact_time"

local LeaderboardUI = {}

LeaderboardUI.BoardKind = {
	Coins = "Coins" :: BoardKind,
	EggsHatched = "EggsHatched" :: BoardKind,
	Time = "Time" :: BoardKind,
}

local function formatCompactTime(totalSec: number): string
	local sec = math.max(0, math.floor(totalSec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then
		return `{h}h {m}m`
	elseif m > 0 then
		return `{m}m {s}s`
	end
	return `{s}s`
end

function LeaderboardUI.FormatScore(boardKind: BoardKind, score: number, valueFormat: ValueFormat?): string
	if valueFormat == "compact_time" then
		return formatCompactTime(score)
	end
	if valueFormat == nil and boardKind == "Time" then
		return formatCompactTime(score)
	end
	return tostring(math.floor(score))
end

local function setText(parent: Instance, name: string, text: string)
	local inst = parent:FindFirstChild(name)
	if inst and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		(inst :: TextLabel).Text = text
	end
end

local function setImage(parent: Instance, name: string, asset: string)
	local inst = parent:FindFirstChild(name)
	if inst and (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) then
		(inst :: ImageLabel).Image = asset
	end
end

--- Fills template children Rank / Name / Value / Head. Head uses rbxthumb (works on server + client).
function LeaderboardUI.ApplyRow(row: Instance, entry: RowEntry, boardKind: BoardKind, valueFormat: ValueFormat?)
	setText(row, "Rank", tostring(entry.rank))
	setText(row, "Name", entry.displayName)
	setText(row, "Value", LeaderboardUI.FormatScore(boardKind, entry.score, valueFormat))
	local thumb = `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=150&h=150`
	setImage(row, "Head", thumb)
end

return LeaderboardUI
