local socket = require("socket")
local json = require("dkjson") -- dkjson must be in the same directory as this script

local server = assert(socket.bind("127.0.0.1", 8090))
local ip, port = server:getsockname()

print("API Server running on " .. ip .. ":" .. port)

while true do
    local client = server:accept()
    client:settimeout(10)

    local request, err = client:receive()
    if not request then
        print("Error receiving request: " .. (err or "unknown"))
        client:close()
    else
        print("Request received: " .. request)

        -- Parse the HTTP request
        local method, path = request:match("^(%S+)%s(%S+)%sHTTP")

        if method == "GET" and path == "/api/teams" then
            -- Dynamically generate JSON with dkjson
            local teams = {
                { team_number = 1114, nickname = "Simbotics", rank = 1 },
                { team_number = 254, nickname = "The Cheesy Poofs", rank = 2 },
                { team_number = 1678, nickname = "Citrus Circuits", rank = 3 }
            }
            local json_response = json.encode(teams)

            local response = "HTTP/1.1 200 OK\r\n"
                .. "Content-Type: application/json\r\n"
                .. "Content-Length: " .. #json_response .. "\r\n\r\n"
                .. json_response
            client:send(response)
        else
            local response = "HTTP/1.1 404 Not Found\r\n\r\n"
            client:send(response)
        end
    end

    client:close()
end
