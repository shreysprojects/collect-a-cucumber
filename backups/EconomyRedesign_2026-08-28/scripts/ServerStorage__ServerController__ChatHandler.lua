-- Modern chat is handled by TextChatService.
-- This module is kept as a compatibility shim for older server loaders that require ChatHandler.

local module = {}

function module.Initialize()
	-- Legacy speaker tag setup was removed during the TextChatService migration.
end

function module.AddTag(_playerName, _tagInfo)
	-- No-op: TextChatService name decoration should be handled with OnIncomingMessage on the client.
end

return module
