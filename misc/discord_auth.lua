local json = require("json")

local CALLBACK_PORT = 8789
local CALLBACK_PATH = "/callback"
local AUTH_ENDPOINT = "/api/auth/game-auth"

local auth_thread = nil
local auth_callback_channel = nil
local auth_loading = false

-- Profile data storage
MP.DISCORD_AUTH.profile_data = nil
local profile_loading = false
local profile_thread = nil
local profile_channel = nil

-- Base64 encoding/decoding using love.data
local function encode_token(token)
	if not token then return nil end
	return love.data.encode("string", "base64", token)
end

local function decode_token(encoded_token)
	if not encoded_token then return nil end
	local success, decoded = pcall(love.data.decode, "string", "base64", encoded_token)
	if success then
		return decoded
	else
		return nil
	end
end

-- Start local HTTP server thread to receive callback
local function start_callback_server()
	if auth_thread then return true end

	-- Create channel for communication
	auth_callback_channel = love.thread.getChannel("discordAuthCallback")

	-- Load and start the auth thread
	local thread_code = MP.load_mp_file("misc/discord_auth.thread.lua")
	if not thread_code then
		sendWarnMessage("Failed to load Discord auth thread", "DISCORD_AUTH")
		return false
	end

	auth_thread = love.thread.newThread(thread_code)
	auth_thread:start(CALLBACK_PORT)

	sendTraceMessage("Discord auth callback server thread started on localhost:" .. CALLBACK_PORT, "DISCORD_AUTH")
	return true
end

-- Check for callback messages from the auth thread
local function check_callback()
	if not auth_callback_channel then return end

	local msg = auth_callback_channel:pop()
	if msg then
		local success, data = pcall(json.decode, msg)
		if success and data then
			if data.error then
				sendWarnMessage("Discord auth thread error: " .. data.error, "DISCORD_AUTH")
			elseif data.token and data.user_id then
				sendTraceMessage("Received callback from auth thread, processing...", "DISCORD_AUTH")
				MP.DISCORD_AUTH.handle_callback(data.token, data.user_id)
			end
		end
	end
end

-- Check for profile data from the profile thread
local function check_profile_data()
	if not profile_channel then return end

	local msg = profile_channel:pop()
	if msg then
		local success, data = pcall(json.decode, msg)
		if success and data then
			if data.success and data.profile then
				-- Profile fetched successfully
				MP.DISCORD_AUTH.profile_data = data.profile
				profile_loading = false
				profile_thread = nil -- Thread will exit after sending data

				sendTraceMessage("Profile data fetched successfully", "DISCORD_AUTH")

				-- Update profile UI
				if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end
			elseif data.error then
				-- Profile fetch failed
				sendWarnMessage("Failed to fetch profile: " .. tostring(data.error), "DISCORD_AUTH")
				profile_loading = false
				profile_thread = nil

				-- Update profile UI to show error state
				if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end
			end
		end
	end
end

-- URL encode a string (simple implementation)
local function url_encode(str)
	if not str then return "" end
	str = string.gsub(str, "([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end

-- Start auth flow
function MP.DISCORD_AUTH.start_auth()
	-- Set loading state
	auth_loading = true

	-- Update profile UI immediately
	if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end

	-- Start callback server if not running
	if not start_callback_server() then
		sendWarnMessage("Failed to start callback server", "DISCORD_AUTH")
		auth_loading = false
		if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end
		return
	end

	-- Build callback URL
	local callback_url = "http://localhost:" .. CALLBACK_PORT .. CALLBACK_PATH
	local encoded_callback = url_encode(callback_url)
	local website_url = SMODS.Mods["Multiplayer"].config.website_url or "http://localhost:3000"
	local auth_url = website_url .. AUTH_ENDPOINT .. "?callback_url=" .. encoded_callback

	sendTraceMessage("Starting Discord auth flow", "DISCORD_AUTH")
	sendTraceMessage("Callback URL: " .. callback_url, "DISCORD_AUTH")
	sendTraceMessage("Encoded callback: " .. encoded_callback, "DISCORD_AUTH")
	sendTraceMessage("Full auth URL: " .. auth_url, "DISCORD_AUTH")

	-- Open browser
	local success = love.system.openURL(auth_url)
	if success then
		sendTraceMessage("Opened Discord auth URL in browser", "DISCORD_AUTH")
	else
		sendWarnMessage("Failed to open browser URL: " .. auth_url, "DISCORD_AUTH")
		auth_loading = false
		if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end
	end
end

-- Handle callback with token and user_id
function MP.DISCORD_AUTH.handle_callback(token, user_id)
	if not token or not user_id then
		sendWarnMessage("Invalid callback: missing token or user_id", "DISCORD_AUTH")
		auth_loading = false
		if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end
		return
	end

	-- Store encoded token and user_id
	SMODS.Mods["Multiplayer"].config.discord_session_token = encode_token(token)
	SMODS.Mods["Multiplayer"].config.discord_user_id = user_id

	-- Save config
	SMODS.save_mod_config(SMODS.Mods["Multiplayer"])

	sendTraceMessage("Discord auth successful for user: " .. user_id, "DISCORD_AUTH")

	-- Clear loading state
	auth_loading = false

	-- Update profile UI
	if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end

	-- Fetch profile data after successful connection
	MP.DISCORD_AUTH.fetch_profile()

	-- Update UI if main menu is open (but not overlay menu)
	if G.MAIN_MENU_UI and not G.OVERLAY_MENU then
		G.MAIN_MENU_UI:remove()
		set_main_menu_UI()
	end
end

-- Get stored session token
function MP.DISCORD_AUTH.get_session_token()
	local encoded = SMODS.Mods["Multiplayer"].config.discord_session_token
	if not encoded then return nil end
	return decode_token(encoded)
end

-- Get stored Discord user ID
function MP.DISCORD_AUTH.get_user_id()
	return SMODS.Mods["Multiplayer"].config.discord_user_id
end

-- Check if connected
function MP.DISCORD_AUTH.is_connected()
	local token = MP.DISCORD_AUTH.get_session_token()
	local user_id = MP.DISCORD_AUTH.get_user_id()
	return token ~= nil and user_id ~= nil
end

-- Check if loading
function MP.DISCORD_AUTH.is_loading()
	return auth_loading
end

-- Disconnect
function MP.DISCORD_AUTH.disconnect()
	SMODS.Mods["Multiplayer"].config.discord_session_token = nil
	SMODS.Mods["Multiplayer"].config.discord_user_id = nil
	SMODS.save_mod_config(SMODS.Mods["Multiplayer"])

	-- Clear profile data
	MP.DISCORD_AUTH.profile_data = nil
	profile_loading = false

	-- Clean up profile thread if running
	if profile_thread then profile_thread = nil end

	sendTraceMessage("Discord disconnected", "DISCORD_AUTH")

	-- Update profile UI
	if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end

	-- Update UI if main menu is open (but not overlay menu)
	if G.MAIN_MENU_UI and not G.OVERLAY_MENU then
		G.MAIN_MENU_UI:remove()
		set_main_menu_UI()
	end
end

-- Get profile data
function MP.DISCORD_AUTH.get_profile_data()
	return MP.DISCORD_AUTH.profile_data
end

-- Check if profile is loading
function MP.DISCORD_AUTH.is_profile_loading()
	return profile_loading
end

-- Fetch profile data from API (now runs in a separate thread)
function MP.DISCORD_AUTH.fetch_profile()
	if not MP.DISCORD_AUTH.is_connected() then return end

	if profile_loading then
		return -- Already fetching
	end

	local user_id = MP.DISCORD_AUTH.get_user_id()
	local token = MP.DISCORD_AUTH.get_session_token()

	if not user_id or not token then return end

	profile_loading = true

	-- Update UI to show loading state
	if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end

	-- Create channel for communication
	profile_channel = love.thread.getChannel("discordProfileData")

	-- Load and start the profile thread
	local thread_code = MP.load_mp_file("misc/discord_profile.thread.lua")
	if not thread_code then
		sendWarnMessage("Failed to load Discord profile thread", "DISCORD_AUTH")
		profile_loading = false
		if MP.UI and MP.UI.Update_BMP_Profile then MP.UI.Update_BMP_Profile() end
		return
	end

	local website_url = SMODS.Mods["Multiplayer"].config.website_url or "http://localhost:3000"
	profile_thread = love.thread.newThread(thread_code)
	profile_thread:start(user_id, token, website_url)

	sendTraceMessage("Started Discord profile fetch thread", "DISCORD_AUTH")
end

-- Update function to check for callbacks and profile data (call this in game update loop)
-- This checks channels for messages from both the auth thread and profile thread
function MP.DISCORD_AUTH.update(dt)
	check_callback()
	check_profile_data()
end
