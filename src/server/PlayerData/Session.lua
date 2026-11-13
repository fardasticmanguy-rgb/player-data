local HttpService = game:GetService("HttpService")

local Template = require(script.Parent.Template)

local MAX_ATTEMPTS = 5
local LOCK_TIMEOUT = 1800
local LOCK_RETRIES = 6
local LOCK_RETRY_DELAY = 5

local JOB_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local Session = {}
Session.__index = Session

export type Session = typeof(setmetatable(
	{} :: {
		Player: Player,
		Key: string,
		Store: DataStore?,
		Data: { [string]: any }?,
		Active: boolean,
		Saving: boolean,
		OnLost: ((Session) -> ())?,
	},
	Session
))

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function reconcile(data: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(data[key]) == "table" and type(value) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function retry<T...>(callback: () -> T...): (boolean, ...any)
	local lastError
	for attempt = 1, MAX_ATTEMPTS do
		local result = table.pack(pcall(callback))
		if result[1] then
			return table.unpack(result, 1, result.n)
		end
		lastError = result[2]
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

local function lockIsForeign(lock: any, force: boolean): boolean
	if type(lock) ~= "table" or lock.JobId == JOB_ID then
		return false
	end
	if force then
		return false
	end
	return os.time() - (tonumber(lock.Time) or 0) < LOCK_TIMEOUT
end

function Session.new(player: Player, store: DataStore?): Session
	return setmetatable({
		Player = player,
		Key = "Player_" .. player.UserId,
		Store = store,
		Data = nil,
		Active = false,
		Saving = false,
		OnLost = nil,
	}, Session)
end

function Session._claim(self: Session, force: boolean): (boolean, boolean)
	local store = self.Store :: DataStore
	local blocked = false
	local loaded = nil
	local ok, err = retry(function()
		return store:UpdateAsync(self.Key, function(record)
			record = if type(record) == "table" then record else {}
			if lockIsForeign(record.Lock, force) then
				blocked = true
				return nil
			end
			blocked = false
			record.Lock = { JobId = JOB_ID, Time = os.time() }
			loaded = record.Data
			return record, { self.Player.UserId }
		end)
	end)
	if not ok then
		warn(`[PlayerData] Could not load {self.Key}: {err}`)
		return false, false
	end
	if not blocked then
		local data = if type(loaded) == "table" then loaded else {}
		reconcile(data, Template)
		self.Data = data
	end
	return true, blocked
end

function Session.Load(self: Session): boolean
	if not self.Store then
		self.Data = deepCopy(Template)
		self.Active = true
		return true
	end
	for attempt = 1, LOCK_RETRIES + 1 do
		local ok, blocked = self:_claim(attempt > LOCK_RETRIES)
		if not ok then
			return false
		end
		if not blocked then
			self.Active = true
			return true
		end
		if self.Player.Parent == nil then
			return false
		end
		task.wait(LOCK_RETRY_DELAY)
	end
	return false
end

function Session._write(self: Session, release: boolean): boolean
	local store = self.Store
	if not store or self.Data == nil then
		return true
	end
	local lost = false
	local ok, err = retry(function()
		return store:UpdateAsync(self.Key, function(record)
			record = if type(record) == "table" then record else {}
			local lock = record.Lock
			if type(lock) == "table" and lock.JobId ~= JOB_ID then
				lost = true
				return nil
			end
			lost = false
			record.Data = self.Data
			record.Lock = if release then nil else { JobId = JOB_ID, Time = os.time() }
			return record, { self.Player.UserId }
		end)
	end)
	if not ok then
		warn(`[PlayerData] Could not save {self.Key}: {err}`)
		return false
	end
	if lost then
		self.Active = false
		warn(`[PlayerData] {self.Key} was taken by another server`)
		if self.OnLost then
			task.spawn(self.OnLost, self)
		end
		return false
	end
	return true
end

function Session.Save(self: Session): boolean
	if not self.Active or self.Saving then
		return false
	end
	self.Saving = true
	local ok = self:_write(false)
	self.Saving = false
	return ok
end

function Session.Release(self: Session): boolean
	if not self.Active then
		return false
	end
	self.Active = false
	while self.Saving do
		task.wait()
	end
	self.Saving = true
	local ok = self:_write(true)
	self.Saving = false
	return ok
end

return Session
