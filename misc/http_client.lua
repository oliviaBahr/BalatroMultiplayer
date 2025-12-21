-- HTTP Client for making requests to the website API
-- Uses LuaSocket's http module for HTTP requests

local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")

MP.HTTP_CLIENT = {}

-- Make a tRPC GET request
-- @param procedure: tRPC procedure path (e.g., "discord.get_user_by_id")
-- @param input: Table of input parameters
-- @param token: Optional session token for authentication
-- @return: success (boolean), response_data (table or nil), error_message (string or nil)
function MP.HTTP_CLIENT.trpc_request(procedure, input, token)
	if not procedure then return false, nil, "Procedure is required" end

	-- Build input object in tRPC format: { "json": {...} }
	local input_obj = {
		json = input or {},
	}

	-- Encode input object as JSON
	local input_json, encode_error = json.encode(input_obj)
	if not input_json then return false, nil, "Failed to encode input: " .. tostring(encode_error) end

	-- URL encode the JSON input for query parameter
	local encoded_input = MP.HTTP_CLIENT.url_encode(input_json)

	-- Build full URL with tRPC GET format: /api/trpc/[procedure]?input={encoded_json}
	local website_url = SMODS.Mods["Multiplayer"].config.website_url or "http://localhost:3000"
	local url = website_url .. "/api/trpc/" .. procedure .. "?input=" .. encoded_input

	-- Prepare headers
	local headers = {
		["Content-Type"] = "application/json",
		["User-Agent"] = "BalatroMultiplayer/1.0",
	}

	-- Add authentication token if provided
	if token then headers["Authorization"] = "Bearer " .. token end

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

-- URL encode a string (kept for backwards compatibility)
function MP.HTTP_CLIENT.url_encode(str)
	if not str then return "" end
	str = tostring(str)
	str = string.gsub(str, "([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end
