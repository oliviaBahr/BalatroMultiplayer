-- Code for Discord profile fetching that runs in a separate thread
-- This allows profile fetching to happen asynchronously without blocking the game thread

-- Since threads run on a separate lua environment, we need to require
-- the necessary modules again
local user_id, token, website_url = ...

require("love.filesystem")
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")

local profileChannel = love.thread.getChannel("discordProfileData")

-- URL encode a string
local function url_encode(str)
	if not str then return "" end
	str = tostring(str)
	str = string.gsub(str, "([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end

-- Make a tRPC GET request (same logic as http_client.lua)
local function trpc_request(procedure, input, auth_token)
	if not procedure then return false, nil, "Procedure is required" end

	-- Build input object in tRPC format: { "json": {...} }
	local input_obj = {
		json = input or {},
	}

	-- Encode input object as JSON
	local input_json, encode_error = json.encode(input_obj)
	if not input_json then return false, nil, "Failed to encode input: " .. tostring(encode_error) end

	-- URL encode the JSON input for query parameter
	local encoded_input = url_encode(input_json)

	-- Build full URL with tRPC GET format: /api/trpc/[procedure]?input={encoded_json}
	local url = website_url .. "/api/trpc/" .. procedure .. "?input=" .. encoded_input

	-- Prepare headers
	local headers = {
		["Content-Type"] = "application/json",
		["User-Agent"] = "BalatroMultiplayer/1.0",
	}

	-- Add authentication token if provided
	if auth_token then headers["Authorization"] = "Bearer " .. auth_token end

	-- Make HTTP GET request
	local response_body = {}
	local request = {
		url = url,
		method = "GET",
		headers = headers,
		sink = ltn12.sink.table(response_body),
	}

	local success, status_code, response_headers = http.request(request)

	if not success then return false, nil, "HTTP request failed: " .. tostring(status_code) end

	-- Check status code
	if status_code ~= 200 then
		local body_text = table.concat(response_body, "")
		return false, nil, "HTTP error " .. tostring(status_code) .. ": " .. body_text
	end

	-- Parse JSON response
	local body_text = table.concat(response_body, "")
	if body_text == "" then return false, nil, "Empty response body" end

	local parse_success, response_data = pcall(json.decode, body_text)
	if not parse_success then return false, nil, "Failed to parse JSON response: " .. tostring(response_data) end

	-- tRPC GET responses are in format: { "result": { "data": { "json": ... } } }
	if response_data and response_data.result then
		if response_data.result.data then
			if response_data.result.data.json then
				return true, response_data.result.data.json, nil
			else
				return true, response_data.result.data, nil
			end
		else
			return true, response_data.result, nil
		end
	elseif response_data and response_data.error then
		return false, nil, "tRPC error: " .. tostring(response_data.error.message or response_data.error)
	end

	-- If response is already the data
	return true, response_data, nil
end

-- Fetch profile data
local function fetch_profile()
	-- Initialize profile data structure
	local profile = {
		username = "Unknown",
		avatar_url = nil,
		ranked_mmr = nil,
		ranked_rank = nil,
		ranked_mmr_change = nil,
		smallworld_mmr = nil,
		smallworld_rank = nil,
		smallworld_mmr_change = nil,
		vanilla_mmr = nil,
		vanilla_rank = nil,
		vanilla_mmr_change = nil,
	}

	-- Fetch Discord user info
	local success, discord_user, error_msg = trpc_request("discord.get_user_by_id", { user_id = user_id }, token)

	if success and discord_user then
		profile.username = discord_user.username or "Unknown"
		profile.avatar_url = discord_user.avatar_url or nil
	else
		-- Send error and exit
		profileChannel:push(json.encode({
			success = false,
			error = "Failed to fetch Discord user info: " .. tostring(error_msg),
		}))
		return
	end

	-- Fetch MMR data for each queue (can be done in parallel with coroutines, but sequential is fine in a thread)
	local queues = {
		{ id = "1", key = "ranked" },
		{ id = "2", key = "smallworld" },
		{ id = "4", key = "vanilla" },
	}

	for _, queue in ipairs(queues) do
		-- Fetch MMR and rank data
		local mmr_success, mmr_data, mmr_error = trpc_request("leaderboard.get_user_rank", {
			channel_id = queue.id,
			user_id = user_id,
			season = "season5",
		}, token)

		if mmr_success and mmr_data and mmr_data.data then
			local mmr_key = queue.key .. "_mmr"
			local rank_key = queue.key .. "_rank"
			profile[mmr_key] = mmr_data.data.mmr or nil
			profile[rank_key] = mmr_data.data.rank or nil
		else
			-- MMR data not available for this queue
			local mmr_key = queue.key .. "_mmr"
			local rank_key = queue.key .. "_rank"
			profile[mmr_key] = nil
			profile[rank_key] = nil
		end

		-- Fetch last game data for mmrChange
		local games_success, games_data, games_error = trpc_request("history.user_games", {
			user_id = user_id,
			queue_id = queue.id,
		}, token)

		if games_success and games_data and type(games_data) == "table" and #games_data > 0 then
			-- Filter games by queueId (backend doesn't filter, so we do it client-side)
			local queue_games = {}
			for _, game in ipairs(games_data) do
				if game.queueId == queue.id then table.insert(queue_games, game) end
			end

			-- Get the first game (most recent) for this queue
			if #queue_games > 0 then
				local last_game = queue_games[1]
				if last_game and last_game.mmrChange ~= nil then
					local mmr_change_key = queue.key .. "_mmr_change"
					profile[mmr_change_key] = last_game.mmrChange
				end
			end
		end
	end

	-- Send success with profile data
	profileChannel:push(json.encode({
		success = true,
		profile = profile,
	}))
end

-- Start fetching profile
fetch_profile()
