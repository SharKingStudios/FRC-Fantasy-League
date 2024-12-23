-- ==========================
-- 1. Configuration
-- ==========================
local user = "sharkingstudios"       -- Adjust to your username
local EVENT_YEAR = "2024"            -- The competition year to fetch event data

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

-- Replace with your Blue Alliance API key
local API_KEY = os.getenv("TBA_API_KEY")

-- ==========================
-- Other things
-- ==========================

-- Folder for robot cards
local cards_folder = "./robotCards"
if not lfs.attributes(cards_folder, "mode") then
  lfs.mkdir(cards_folder)
end

-- Function to read a robot card JSON
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

-- Function to save a robot card JSON
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
-- 3. TBA Helper Functions
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
-- 4. Fetch Team Data (All Events in EVENT_YEAR)
-- ==========================
local function fetch_district_points(team_number)
  local districts = tba_get("team/frc" .. team_number .. "/districts")
  if not districts then return 0 end

  -- Find the district for EVENT_YEAR
  for _, district in ipairs(districts) do
    if district.year == tonumber(EVENT_YEAR) then
      -- Fetch the district ranking points
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

  -- Get district ranking points
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
-- 5. CSV Utility Functions
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
-- 6. Save to CSV
-- ==========================
local function save_to_csv(team_data)
  local filename = "teams.csv"
  local rows, headers = read_csv(filename)

  local required_cols = {
    "team_number", "nickname", "city", "rookie_year",
    "rank", "wins", "losses", "ties", "ranking_points"
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
-- 7. Get Ranked Teams
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
-- 8. Start Lua HTTP Server
-- ==========================
local server = assert(socket.bind("127.0.0.1", 8090))
print("API Server running on 127.0.0.1:8090")

while true do
  local client = server:accept()
  client:settimeout(10)

  local request = client:receive()
  if request then
    local method, path = request:match("^(%S+)%s(%S+)%sHTTP")

    if method == "GET" and path == "/api/teams" then
      local teams = get_ranked_teams()
      local json_response = json.encode(teams)
      local response = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: application/json\r\n\r\n"
        .. json_response
      client:send(response)

    elseif method == "POST" and path:match("^/api/teams/") then
      local team_number = tonumber(path:match("^/api/teams/(%d+)$"))
      local team_data = fetch_team_data(team_number)
      if team_data then
        print("Saving team data for frc" .. team_number)
        print("Data: " .. json.encode(team_data))
        
        -- Step 1: Save/update new team data
        save_to_csv(team_data)
        
        -- Step 2: Resort entire CSV by ranking_points descending
        local filename = "teams.csv"
        local rows, headers = read_csv(filename)
        
        -- Sort by ranking_points descending
        table.sort(rows, function(a, b)
          local rpA = tonumber(a.ranking_points) or 0
          local rpB = tonumber(b.ranking_points) or 0
          return rpA > rpB  -- highest ranking_points first
        end)
        
        -- Step 3: Reassign 'rank' from 1..N in that new order
        for i, row in ipairs(rows) do
          row.rank = i
        end
        
        -- Step 4: Write it back out
        write_csv(filename, rows, headers)
        
        -- Finally respond
        client:send("HTTP/1.1 200 OK\r\n\r\nTeam data saved.\n")
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nFailed to fetch team data.\n")
      end    
    else
      client:send("HTTP/1.1 404 Not Found\r\n\r\n")
    end
  end

  client:close()
end
