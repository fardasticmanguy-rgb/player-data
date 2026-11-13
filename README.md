# player-data

Session-locked player data for Roblox. One module, no dependencies, drop it into `ServerScriptService`.

## Features

- [x] Load and save with retries (exponential backoff, 5 attempts)
- [x] Session locking, so two servers can never write the same player at once
- [x] Template reconciliation, so new fields show up in old saves automatically
- [x] Autosave every 60 seconds
- [x] Safe shutdown, every player is saved and released before the server closes
- [x] Works in Studio without API access (falls back to in-memory data)

## Usage

```lua
local PlayerData = require(ServerScriptService.Server.PlayerData)

PlayerData.Start()

Players.PlayerAdded:Connect(function(player)
	local data = PlayerData.WaitFor(player)
	if data then
		data.Coins += 100
	end
end)
```

| Function | What it does |
| --- | --- |
| `PlayerData.Start()` | Hooks up joins, leaves, autosave and shutdown. Call once. |
| `PlayerData.Get(player)` | The player's data table, or `nil` if it isn't loaded. |
| `PlayerData.WaitFor(player)` | Yields until the data is loaded. Returns `nil` if loading failed or the player left. |
| `PlayerData.Save(player)` | Saves right away. Useful after a purchase. |

Change the data shape in `Template.lua`. Anything missing from a saved profile is filled in from it on load, nested tables included.

## How it works

Each save is stored as `{ Data, Lock }`, where `Lock` holds the server's `JobId` and a timestamp. Every read and write goes through `UpdateAsync`.

1. **Join**: the server tries to claim the lock. If another server still holds a fresh one (usually the server the player just left, still saving), it waits and tries again. After about 30 seconds it takes the lock over.
2. **Play**: autosaves refresh the lock. If a save finds that another server has taken the lock, this server stops writing and kicks the player, so stale data can never overwrite newer data.
3. **Leave**: the final save writes the data and clears the lock in one update, so the next server can load straight away.
4. **Shutdown**: `BindToClose` releases every session in parallel and waits up to 25 seconds for them to finish.

Locks older than 30 minutes count as abandoned (for example after a server crash) and are taken over immediately. Every write tags the player's `UserId` so GDPR removal requests find the key.

## Setup

```
rojo serve
```

Connect from the Rojo plugin in Studio. To save for real, publish the place and turn on **Enable Studio Access to API Services** in Game Settings.
