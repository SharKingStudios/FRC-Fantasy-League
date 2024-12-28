-- ==========================
-- 1. Configuration
-- ==========================
local user = "sharkingstudios"
local EVENT_YEAR = "2024"

-- Update Lua paths for local LuaRocks
package.path = package.path
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?.lua"
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?/init.lua"

package.cpath = package.cpath
  .. ";/home/" .. user .. "/.luarocks/lib/lua/5.3/?.so"

-- ==========================
-- 2. Required Modules
-- ==========================
local socket = require("socket")
local json = require("dkjson")
local http_request = require("http.request")
local lfs = require("lfs")
local lanes = require("lanes").configure()

-- Replace with your Blue Alliance API key
local API_KEY = os.getenv("TBA_API_KEY")

-- ==========================
-- 3. Folders & Setup
-- ==========================
local cards_folder = "./robotCards"
if not lfs.attributes(cards_folder, "mode") then
  lfs.mkdir(cards_folder)
end

local robot_images_folder = "./robotImages"
if not lfs.attributes(robot_images_folder, "mode") then
  lfs.mkdir(robot_images_folder)
end

-- ==========================
-- 4. Helper: read/write JSON Card
-- ==========================
local function get_robot_card(team_number)
  local card_path = cards_folder .. "/" .. team_number .. ".json"
  local file = io.open(card_path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return json.decode(content)
  end
  return nil
end

local function save_robot_card(team_number, card_data)
  local card_path = cards_folder .. "/" .. team_number .. ".json"
  local file = io.open(card_path, "w")
  if file then
    file:write(json.encode(card_data))
    file:close()
    return true
  end
  return false
end

-- ==========================
-- 5. TBA Helper Functions
-- ==========================
local function tba_get(path)
  local url = "https://www.thebluealliance.com/api/v3/" .. path
  local req = http_request.new_from_uri(url)
  req.headers:upsert(":method", "GET")
  req.headers:upsert("x-tba-auth-key", API_KEY)

  local headers, stream = req:go()
  if not headers then
    print("Error fetching " .. path .. ": request failed.")
    return nil
  end

  local body = stream:get_body_as_string()
  stream:shutdown()
  return json.decode(body)
end

-- ==========================
-- 6. Team Data (Fetch from TBA)
-- ==========================
local function fetch_district_points(team_number)
  local districts = tba_get("team/frc" .. team_number .. "/districts")
  if not districts then return 0 end

  for _, district in ipairs(districts) do
    if district.year == tonumber(EVENT_YEAR) then
      local district_key = district.key
      local district_ranking = tba_get("district/" .. district_key .. "/rankings")
      if district_ranking then
        for _, rank_entry in ipairs(district_ranking) do
          if rank_entry.team_key == "frc" .. team_number then
            return rank_entry.point_total or 0
          end
        end
      end
    end
  end
  return 0
end

local function fetch_team_data(team_number)
  local team_info = tba_get("team/frc" .. team_number)
  if not team_info then return nil end

  local events = tba_get("team/frc" .. team_number .. "/events/" .. EVENT_YEAR)
  if not events or #events == 0 then
    return {
      team_number = team_info.team_number or team_number,
      nickname = team_info.nickname or "",
      city = team_info.city or "",
      rookie_year = team_info.rookie_year or 0,
      rank = 0, wins=0, losses=0, ties=0, ranking_points=0
    }
  end

  local best_rank = 999999
  local total_wins, total_losses, total_ties = 0, 0, 0

  for _, ev in ipairs(events) do
    if ev.event_type == 99 then
      -- Skip off-season events
      goto continue
    end

    local status_info = tba_get("team/frc" .. team_number .. "/event/" .. ev.key .. "/status")
    if status_info then
      local qual_ranking = status_info.qual and status_info.qual.ranking
      local qual_record  = (qual_ranking and qual_ranking.record) or {}
      local qual_rank    = (qual_ranking and qual_ranking.rank)   or 999999

      local playoff      = status_info.playoff
      local playoff_rec  = (playoff and playoff.record) or {}

      local eventWins   = (qual_record.wins   or 0) + (playoff_rec.wins   or 0)
      local eventLosses = (qual_record.losses or 0) + (playoff_rec.losses or 0)
      local eventTies   = (qual_record.ties   or 0) + (playoff_rec.ties   or 0)

      if qual_rank < best_rank then
        best_rank = qual_rank
      end

      total_wins   = total_wins   + eventWins
      total_losses = total_losses + eventLosses
      total_ties   = total_ties   + eventTies

      print(string.format(
        "Event %s => Q+P record: %d-%d-%d, rank=%d => totals: %d-%d-%d",
        ev.key, eventWins, eventLosses, eventTies, qual_rank, total_wins, total_losses, total_ties
      ))
    end

    ::continue::
  end

  local district_points = fetch_district_points(team_number)

  local combined = {
    team_number    = team_info.team_number or team_number,
    nickname       = team_info.nickname    or "",
    city           = team_info.city        or "",
    rookie_year    = team_info.rookie_year or 0,
    rank           = best_rank < 999999 and best_rank or 0,
    wins           = total_wins,
    losses         = total_losses,
    ties           = total_ties,
    ranking_points = district_points
  }

  print("FINAL combined for frc" .. team_number .. ": " .. json.encode(combined))
  return combined
end

-- ==========================
-- 7. CSV Utility
-- ==========================
local function row_to_csv(row, headers)
  local parts = {}
  for _, col in ipairs(headers) do
    local value = row[col] or ""
    table.insert(parts, tostring(value))
  end
  return table.concat(parts, ",")
end

local function csv_to_row(line, headers)
  local fields = {}
  for field in string.gmatch(line, "([^,]+)") do
    table.insert(fields, field)
  end
  local row = {}
  for i, col in ipairs(headers) do
    row[col] = fields[i] or ""
  end
  return row
end

local function read_csv(filename)
  local file = io.open(filename, "r")
  if not file then
    return {}, {}
  end

  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  if #lines == 0 then
    return {}, {}
  end

  local headers = {}
  for header in string.gmatch(lines[1], "([^,]+)") do
    table.insert(headers, header)
  end

  local rows = {}
  for i = 2, #lines do
    local row = csv_to_row(lines[i], headers)
    table.insert(rows, row)
  end

  return rows, headers
end

local function write_csv(filename, rows, headers)
  local file = io.open(filename, "w")
  if not file then
    return
  end

  file:write(table.concat(headers, ",") .. "\n")
  for _, row in ipairs(rows) do
    local line = row_to_csv(row, headers)
    file:write(line .. "\n")
  end
  file:close()
end

-- ==========================
-- 8. Save to CSV
-- ==========================
local function save_to_csv(team_data)
  local filename = "teams.csv"
  local rows, headers = read_csv(filename)

  local required_cols = {
    "team_number", "nickname", "city", "rookie_year",
    "rank", "wins", "losses", "ties", "ranking_points"
    -- Add extra columns if needed for card creation
    -- e.g. 'image_path', 'hitpoints', 'flavor_text', etc.
  }

  local header_map = {}
  for _, h in ipairs(headers) do
    header_map[h] = true
  end
  for _, rc in ipairs(required_cols) do
    if not header_map[rc] then
      table.insert(headers, rc)
      header_map[rc] = true
    end
  end

  -- Convert rows into a map for quick lookup
  local row_map = {}
  for _, row in ipairs(rows) do
    row_map[row.team_number] = row
  end

  local key = tostring(team_data.team_number)
  local row = row_map[key]
  if not row then
    row = {}
    row_map[key] = row
    table.insert(rows, row)
  end

  for _, col in ipairs(required_cols) do
    row[col] = team_data[col] or ""
  end

  write_csv(filename, rows, headers)
end

-- ==========================
-- 9. Ranking
-- ==========================
local function get_ranked_teams()
  local filename = "teams.csv"
  local rows, headers = read_csv(filename)
  if #rows == 0 then
    return {}
  end

  table.sort(rows, function(a, b)
    local rankA = tonumber(a.rank) or 999999
    local rankB = tonumber(b.rank) or 999999
    return rankA < rankB
  end)

  return rows
end

-- ==========================
-- 10. Integrate with Python Card Creator
-- ==========================
--- Example function to POST data to the Python server at /create-card
local function create_card_via_python(card_data)
  local body = json.encode(card_data)

  local req = http_request.new_from_uri("http://sharkingstudios.hackclub.app:8091/create-card")
  req.headers:upsert(":method", "POST")
  req.headers:upsert("content-type", "application/json")
  req:set_body(body)

  local headers, stream = req:go()
  if not headers then
    return false, "Failed to connect to python server"
  end

  local status = tonumber(headers:get(":status"))
  local response_body = stream:get_body_as_string()
  stream:shutdown()

  if status ~= 200 then
    return false, "Python server error: " .. tostring(status) .. " => " .. response_body
  end

  -- Parse JSON response
  local resp_json = json.decode(response_body) or {}
  if resp_json.status == "success" then
    return true, resp_json.card_path
  else
    return false, resp_json.message or "Unknown error"
  end
end

-- Utility function to check if a file exists
local function file_exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  else
    return false
  end
end

-- Helper to read from CSV and build the JSON for the Python server
local function build_card_data_from_csv(team_number)
  -- This is where you shape the data for create_card
  local rows, headers = read_csv("teams.csv")
  
  -- Create image path
  for _, row in ipairs(rows) do
    if row.team_number == tostring(team_number) then
      -- Determine the image path
      local image_path = row.image_path
      if not image_path or image_path == "" then
        -- Attempt to find a .png image
        local png_path = "./images/robotImages/" .. row.team_number .. ".png"
        if file_exists(png_path) then
          image_path = png_path
        else
          -- Attempt to find a .jpeg image
          local jpeg_path = "./images/robotImages/" .. row.team_number .. ".jpeg"
          if file_exists(jpeg_path) then
            image_path = jpeg_path
          else
            -- Handle the case where neither image exists
            -- Option 1: Set to a default image
            image_path = "./images/robotImages/default.png"  -- Ensure this default image exists
            -- Option 2: Return an error or handle accordingly
            -- return nil, "Image file not found for team number: " .. row.team_number
          end
        end
      end

      -- Return the structured data
      return {
        team_number = row.team_number,
        team_name   = row.nickname or ("Team " .. row.team_number),
        image_path  = image_path,
        flavor_text = row.flavor_text or "",
        hitpoints   = row.hitpoints or "150",
        custom_label = "No." .. row.team_number .. "FRC",
        image_x = row.image_x or 0,
        image_y = row.image_y or 0,
        image_zoom = row.image_zoom or 1.0
        -- Add other fields as necessary
      }
    end
  end

  -- If the team number wasn't found in the CSV
  return nil
end

local function updateCardForTeam(team_number)
  -- 1. Optionally, fetch/update from TBA
  local tba_data = fetch_team_data(team_number)
  if tba_data then
    save_to_csv(tba_data)
  end

  -- 2. Build the card data from CSV
  local card_data = build_card_data_from_csv(team_number)
  if not card_data then
    return false, "Team not found in CSV or missing image_path"
  end

  -- 3. Call the python server
  local success, result = create_card_via_python(card_data)
  return success, result
end

-- ==========================
-- 11. Start Lua HTTP Server
-- ==========================
local server = assert(socket.bind("127.0.0.1", 8090))
print("API Server running on 127.0.0.1:8090")

while true do
  local client = server:accept()
  client:settimeout(10)

  local request = client:receive()
  if request then
    local method, path = request:match("^(%S+)%s(%S+)%sHTTP")

    ------------------------------------------------------------------------------
    -- Existing GET /api/teams (returns JSON array of teams from CSV)
    ------------------------------------------------------------------------------
    if method == "GET" and path == "/api/teams" then
      local teams = get_ranked_teams()
      local json_response = json.encode(teams)
      local response = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: application/json\r\n\r\n"
        .. json_response
      client:send(response)

    ------------------------------------------------------------------------------
    -- Existing POST /api/teams/<TEAM_NUMBER> (fetch from TBA, update CSV ranking)
    ------------------------------------------------------------------------------
    elseif method == "POST" and path:match("^/api/teams/") then
      local team_number = tonumber(path:match("^/api/teams/(%d+)$"))
      local team_data = fetch_team_data(team_number)
      if team_data then
        print("Saving team data for frc" .. team_number)
        print("Data: " .. json.encode(team_data))
        
        -- 1. Save/update new team data
        save_to_csv(team_data)
        
        -- 2. Resort entire CSV by ranking_points descending
        local filename = "teams.csv"
        local rows, headers = read_csv(filename)
        table.sort(rows, function(a, b)
          local rpA = tonumber(a.ranking_points) or 0
          local rpB = tonumber(b.ranking_points) or 0
          return rpA > rpB
        end)
        
        -- 3. Reassign 'rank' from 1..N
        for i, row in ipairs(rows) do
          row.rank = i
        end
        -- 4. Write it back out
        write_csv(filename, rows, headers)
        
        client:send("HTTP/1.1 200 OK\r\n\r\nTeam data saved.\n")
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nFailed to fetch team data.\n")
      end

    ------------------------------------------------------------------------------
    -- Serve Robot Card Images (static) => GET /api/robotCards/<filename.png>
    ------------------------------------------------------------------------------
    elseif method == "GET" and path:match("^/api/robotCards/") then
      local relative_path = path:match("^/api/robotCards/(.+)$")
      if relative_path then
        local file_path = cards_folder .. "/" .. relative_path
        local file = io.open(file_path, "rb")
        if file then
          local content = file:read("*a")
          file:close()

          local content_type = "image/png"  -- or detect by extension
          local response = "HTTP/1.1 200 OK\r\n"
            .. "Content-Type: " .. content_type .. "\r\n\r\n"
          client:send(response)
          client:send(content)
        else
          client:send("HTTP/1.1 404 Not Found\r\n\r\n")
        end
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\n")
      end

    ------------------------------------------------------------------------------
    -- NEW: GET /api/teams.csv => Serve CSV as text/csv
    ------------------------------------------------------------------------------
    elseif method == "GET" and path == "/api/teams.csv" then
      local file = io.open("teams.csv", "r")
      if file then
        local content = file:read("*a")
        file:close()
        local response = "HTTP/1.1 200 OK\r\n"
          .. "Content-Type: text/csv\r\n\r\n"
          .. content
        client:send(response)
      else
        client:send("HTTP/1.1 404 Not Found\r\n\r\n")
      end

    ------------------------------------------------------------------------------
    -- NEW: POST /api/admin/updateAllCards => Loop through CSV & call python server
    ------------------------------------------------------------------------------
    elseif method == "POST" and path == "/api/admin/updateAllCards" then
      local rows, headers = read_csv("teams.csv")
      local results = {}

      for _, row in ipairs(rows) do
        local tnum = row.team_number
        if tnum and tnum:match("^%d+$") then
          local success, res = updateCardForTeam(tnum)
          table.insert(results, {
            team_number = tnum,
            status = success and "OK" or ("ERROR: " .. tostring(res))
          })
        end
      end

      local json_response = json.encode(results)
      local response = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: application/json\r\n\r\n"
        .. json_response
      client:send(response)

    ------------------------------------------------------------------------------
    -- NEW: POST /api/admin/updateCard/<TEAM_NUMBER> => Single card update
    ------------------------------------------------------------------------------
    elseif method == "POST" and path:match("^/api/admin/updateCard/") then
      local tnum = path:match("^/api/admin/updateCard/(%d+)$")
      if tnum then
        local success, res = updateCardForTeam(tnum)
        if success then
          client:send("HTTP/1.1 200 OK\r\n\r\nTeam " .. tnum .. " card updated. \n")
        else
          client:send("HTTP/1.1 500 Internal Server Error\r\n\r\n" .. tostring(res) .. "\n")
        end
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing or invalid team number.\n")
      end

    ------------------------------------------------------------------------------
    -- NEW: POST /api/admin/uploadRobotImage => Skeleton for file upload
    ------------------------------------------------------------------------------
    elseif method == "POST" and path == "/api/admin/uploadRobotImage" then
      -- This is where you'd parse the incoming multipart/form-data.
      -- SKELETON approach: Read raw request, parse boundaries, etc.
      -- The below is only a demonstration of the high-level steps.

      -- 1. Read HTTP headers and content length
      local content_length = 0
      local request_headers = {}
      repeat
        local header_line = client:receive()
        if not header_line or header_line == "" then break end
        table.insert(request_headers, header_line)
        local cl = header_line:match("^Content%-Length:%s*(%d+)")
        if cl then content_length = tonumber(cl) or 0 end
      until false

      -- 2. Read the POST body. (For real-world usage, you'd parse the boundary.)
      local raw_body = client:receive(content_length)

      -- TODO: Properly parse form data. For example, get:
      --   teamNumber
      --   the file (binary)
      --   filename
      -- Save file into /robotImages/<teamNumber>.png or similar.

      -- For now, just respond with a placeholder:
      client:send("HTTP/1.1 200 OK\r\n\r\nUpload route not fully implemented.\n")

    ------------------------------------------------------------------------------
    -- Unrecognized path
    ------------------------------------------------------------------------------
    else
      client:send("HTTP/1.1 404 Not Found\r\n\r\n")
    end
  end

  client:close()
end
