-- Each player's saved progress: class, level, XP and quests. Loaded on join, saved on leave,
-- every few minutes and when the server shuts down. One DataStore key per player
-- ("player_<UserId>"), with a `version` field so old saves can be upgraded.
--
-- Studio uses its own store, so test saves never touch real players' progress. DataStores in
-- Studio need Game Settings > Security > "Enable Studio Access to API Services".
-- If a save can't be loaded, the player still plays but nothing is saved that session, so a
-- good save is never overwritten with a blank one.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassData = require(Shared:WaitForChild("ClassData"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local PlayerData = {}

local SAVE_VERSION = 2 -- 2: added inventory and gifts
local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
local AUTOSAVE_INTERVAL = 180
local RETRIES = 3

export type QuestState = { status: string, progress: number } -- status: "active" | "ready" | "done"
export type Data = {
	version: number,
	class: string?,
	level: number,
	xp: number,
	quests: { [string]: QuestState },
	inventory: { [string]: number }, -- item id -> count
	gifts: { [string]: boolean }, -- one-off gifts already given (e.g. the Elder's potions)
}

local toastEvent = Net.event("Toast")
local levelUpEvent = Net.event("LevelUp")

local profiles: { [Player]: Data } = {}
local canSave: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local waiting: { [Player]: { thread } } = {}
local loadedListeners: { (Player) -> () } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable, progress won't be saved:", result)
	end
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function newData(): Data
	return { version = SAVE_VERSION, class = nil, level = 1, xp = 0, quests = {}, inventory = {}, gifts = {} }
end

-- Fills in anything missing and upgrades old versions. Add a step here whenever SAVE_VERSION goes up.
local function migrate(raw: any): Data
	if type(raw) ~= "table" then
		return newData()
	end
	local data = raw :: Data
	data.version = SAVE_VERSION
	data.level = math.clamp(tonumber(data.level) or 1, 1, Progression.MAX_LEVEL)
	data.xp = math.max(0, tonumber(data.xp) or 0)
	if type(data.quests) ~= "table" then
		data.quests = {}
	end
	-- Version 1 saves had no inventory or gifts.
	if type(data.inventory) ~= "table" then
		data.inventory = {}
	end
	if type(data.gifts) ~= "table" then
		data.gifts = {}
	end
	if data.class ~= nil and not ClassData.get(data.class) then
		data.class = nil
	end
	return data
end

-- Copies level and XP onto the player as attributes, which replicate to every client.
local function publish(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	player:SetAttribute("Level", data.level)
	player:SetAttribute("XP", data.xp)
	player:SetAttribute("XPNext", Progression.xpToNext(data.level))
	player:SetAttribute("SavedClass", data.class)
end

local function load(player: Player)
	local data: Data? = nil
	local ok = store ~= nil
	if store then
		ok = false
		for attempt = 1, RETRIES do
			local success, result = pcall(function()
				return (store :: DataStore):GetAsync(key(player))
			end)
			if success then
				data = migrate(result)
				ok = true
				break
			end
			warn(`[PlayerData] Loading {player.Name} failed (try {attempt}):`, result)
			if string.find(tostring(result), "Studio access", 1, true) then
				warn("[PlayerData] Turn on Game Settings > Security > Enable Studio Access to API Services to test saving in Studio.")
				break -- retrying won't help
			end
			if not player.Parent then
				break
			end
			task.wait(attempt * 2)
		end
	end
	if not player.Parent then
		return
	end
	profiles[player] = data or newData()
	canSave[player] = ok
	if not ok then
		toastEvent:FireClient(player, "Progress couldn't be loaded, so it won't be saved this time")
	end
	publish(player)
	player:SetAttribute("DataLoaded", true)
	for _, thread in waiting[player] or {} do
		task.spawn(thread, profiles[player])
	end
	waiting[player] = nil
	for _, listener in loadedListeners do
		task.spawn(listener, player)
	end
end

-- Saves now if anything changed (or always, with `force`). Returns true when saved.
function PlayerData.save(player: Player, force: boolean?): boolean
	local data = profiles[player]
	if not data or not canSave[player] or not store then
		return false
	end
	if not force and not dirty[player] then
		return true
	end
	dirty[player] = false
	for attempt = 1, RETRIES do
		local success, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(player), function()
				return data
			end)
		end)
		if success then
			return true
		end
		warn(`[PlayerData] Saving {player.Name} failed (try {attempt}):`, err)
		task.wait(attempt)
	end
	dirty[player] = true
	return false
end

function PlayerData.get(player: Player): Data?
	return profiles[player]
end

-- Waits until the player's save has loaded. Returns nil if they leave first.
function PlayerData.whenLoaded(player: Player): Data?
	if profiles[player] then
		return profiles[player]
	end
	if not player.Parent then
		return nil
	end
	waiting[player] = waiting[player] or {}
	table.insert(waiting[player], coroutine.running())
	return coroutine.yield()
end

-- Runs `listener(player)` each time a player's save finishes loading.
function PlayerData.onLoaded(listener: (Player) -> ())
	table.insert(loadedListeners, listener)
end

function PlayerData.markDirty(player: Player)
	dirty[player] = true
end

function PlayerData.setClass(player: Player, classId: string)
	local data = profiles[player]
	if data and data.class ~= classId then
		data.class = classId
		dirty[player] = true
		publish(player)
	end
end

-- Gives XP and handles level-ups. `reason` (e.g. "Wolf defeated") is shown in a toast.
function PlayerData.addXP(player: Player, amount: number, reason: string?)
	local data = profiles[player]
	if not data or amount <= 0 then
		return
	end
	if reason then
		toastEvent:FireClient(player, `{reason} (+{amount} XP)`)
	end
	if data.level >= Progression.MAX_LEVEL then
		return
	end
	data.xp += amount
	local levelled = false
	while data.level < Progression.MAX_LEVEL and data.xp >= Progression.xpToNext(data.level) do
		data.xp -= Progression.xpToNext(data.level)
		data.level += 1
		levelled = true
	end
	if data.level >= Progression.MAX_LEVEL then
		data.xp = 0
	end
	dirty[player] = true
	publish(player) -- PlayerSetup watches the Level attribute and raises max health
	if levelled then
		levelUpEvent:FireAllClients(player, data.level)
	end
end

local started = false
function PlayerData.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerData.save(player, true)
		for _, thread in waiting[player] or {} do
			task.spawn(thread, nil)
		end
		waiting[player] = nil
		profiles[player] = nil
		canSave[player] = nil
		dirty[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerData.save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
