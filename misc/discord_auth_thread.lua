-- Code for Discord auth callback server that runs in a separate thread

-- Since threads run on a separate lua environment, we need to require
-- the necessary modules again
return [[
local CALLBACK_PORT = ...
local CALLBACK_PATH = "/callback"

require("love.filesystem")
local socket = require("socket")
local json = require("json")

local local_server = nil
local server_running = false
local authCallbackChannel = love.thread.getChannel("discordAuthCallback")

-- Start local HTTP server to receive callback
local function start_callback_server()
    if server_running then
        return true
    end

    local success, err = pcall(function()
        local_server = socket.bind("localhost", CALLBACK_PORT)
        if not local_server then
            return false
        end

        -- Set server socket options
        local_server:setoption("reuseaddr", true)
        local_server:settimeout(0.1) -- Non-blocking
        server_running = true
        return true
    end)

    if not success then
        return false
    end

    return success
end

-- Check for incoming callback requests
local function check_callback()
    if not server_running or not local_server then
        return
    end

    local client = local_server:accept()
    if client then
        client:settimeout(1)
        local request = client:receive("*l")

        if request then
            -- Parse GET request
            local method, path = string.match(request, "^(%w+)%s+(%S+)%s+HTTP")

            if method == "GET" and string.find(path, CALLBACK_PATH) then
                -- Extract query parameters
                local query_string = string.match(path, "%?(.+)")
                if query_string then
                    local token = nil
                    local user_id = nil

                    -- Parse query params
                    for pair in string.gmatch(query_string, "([^&]+)") do
                        local key, value = string.match(pair, "([^=]+)=(.+)")
                        if key == "token" then
                            token = value
                        elseif key == "user_id" then
                            user_id = value
                        end
                    end

                    if token and user_id then
                        -- URL decode
                        token = string.gsub(token, "%%(%x%x)", function(hex)
                            return string.char(tonumber(hex, 16))
                        end)
                        user_id = string.gsub(user_id, "%%(%x%x)", function(hex)
                            return string.char(tonumber(hex, 16))
                        end)

                        -- Send callback data to main thread
                        authCallbackChannel:push(json.encode({
                            token = token,
                            user_id = user_id
                        }))

                        -- Send success response
                        local response = "HTTP/1.1 200 OK\r\n"
                        response = response .. "Content-Type: text/html\r\n"
                        response = response .. "Connection: close\r\n\r\n"
                        response = response ..
                            "<html><body><h1>Discord Connected Successfully!</h1><p>You can close this window.</p></body></html>"
                        client:send(response)
                    else
                        -- Send error response
                        local response = "HTTP/1.1 400 Bad Request\r\n"
                        response = response .. "Content-Type: text/html\r\n"
                        response = response .. "Connection: close\r\n\r\n"
                        response = response .. "<html><body><h1>Error</h1><p>Missing token or user_id</p></body></html>"
                        client:send(response)
                    end
                else
                    -- No query params
                    local response = "HTTP/1.1 400 Bad Request\r\n"
                    response = response .. "Content-Type: text/html\r\n"
                    response = response .. "Connection: close\r\n\r\n"
                    response = response .. "<html><body><h1>Error</h1><p>Missing parameters</p></body></html>"
                    client:send(response)
                end
            else
                -- Not our callback path, send 404
                local response = "HTTP/1.1 404 Not Found\r\n"
                response = response .. "Connection: close\r\n\r\n"
                client:send(response)
            end
        end

        client:close()
    end
end

-- Initialize server
if not start_callback_server() then
    -- Signal error to main thread
    authCallbackChannel:push(json.encode({
        error = "Failed to start callback server"
    }))
end

-- Main loop - check for callbacks periodically
while true do
    check_callback()
    -- Sleep for 100ms to avoid busy waiting
    socket.sleep(0.1)
end
]]
