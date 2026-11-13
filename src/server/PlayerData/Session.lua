local Session = {}
Session.__index = Session

function Session.new(player: Player, store: DataStore)
end

function Session:Load(): boolean
end

function Session:Save(): boolean
end

function Session:Release()
end

return Session
