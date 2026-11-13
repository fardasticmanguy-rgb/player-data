local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Session = require(script.Session)

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 60
local SHUTDOWN_TIMEOUT = 25

local PlayerData = {}

local sessions: { [Player]: Session.Session } = {}
local loading: { [Player]: boolean } = {}
local changed = Instance.new("BindableEvent")
local inFlight = 0
local started = false
local closing = false
local store: DataStore? = nil

local function track(callback: () -> ())
	inFlight += 1
	local ok, err = pcall(callback)
	inFlight -= 1
	if not ok then
		warn(`[PlayerData] {err}`)
	end
end

local function openStore(): DataStore?
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok then
		return result
	end
	warn(`[PlayerData] DataStores unavailable, data will not be saved: {result}`)
	return nil
end

local function onLost(session: Session.Session)
	local player = session.Player
	if sessions[player] == session then
		sessions[player] = nil
		changed:Fire(player)
	end
	if player.Parent then
		player:Kick("Your data was opened on another server. Please rejoin.")
	end
end

local function onPlayerAdded(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	track(function()
		local session = Session.new(player, store)
		session.OnLost = onLost
		if not session:Load() then
			if player.Parent then
				player:Kick("Your data could not be loaded. Please rejoin in a minute.")
			end
			return
		end
		if closing or player.Parent == nil then
			session:Release()
			return
		end
		sessions[player] = session
	end)
	loading[player] = nil
	changed:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	changed:Fire(player)
	if session then
		track(function()
			session:Release()
		end)
	end
end

local function autosave()
	while not closing do
		task.wait(AUTOSAVE_INTERVAL)
		for _, session in sessions do
			task.spawn(session.Save, session)
		end
	end
end

local function onClose()
	closing = true
	for player in sessions do
		task.spawn(onPlayerRemoving, player)
	end
	local deadline = os.clock() + SHUTDOWN_TIMEOUT
	while inFlight > 0 and os.clock() < deadline do
		task.wait()
	end
end

function PlayerData.Get(player: Player): { [string]: any }?
	local session = sessions[player]
	return if session then session.Data else nil
end

function PlayerData.WaitFor(player: Player): { [string]: any }?
	while not sessions[player] and player.Parent and (loading[player] or not started) do
		changed.Event:Wait()
	end
	return PlayerData.Get(player)
end

function PlayerData.Save(player: Player): boolean
	local session = sessions[player]
	return if session then session:Save() else false
end

function PlayerData.Start()
	if started then
		return
	end
	started = true
	store = openStore()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(onClose)
	task.spawn(autosave)
end

return PlayerData
