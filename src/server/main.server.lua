local Players = game:GetService("Players")

local PlayerData = require(script.Parent.PlayerData)

PlayerData.Start()

local function showStats(player: Player)
	local data = PlayerData.WaitFor(player)
	if not data then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = leaderstats
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = data.Level
	level.Parent = leaderstats
	leaderstats.Parent = player
	while player.Parent and PlayerData.Get(player) == data do
		task.wait(1)
		coins.Value = data.Coins
		level.Value = data.Level
	end
end

Players.PlayerAdded:Connect(showStats)
for _, player in Players:GetPlayers() do
	task.spawn(showStats, player)
end
