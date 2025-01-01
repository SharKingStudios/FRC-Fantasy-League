-- card_creation_service.lua
-- Continuously polls "jobs.csv" for queued/running jobs, executes them,
-- updates their status & job_data.

------------------------------------------------------------------------------
-- 1. Configuration & Required Modules
------------------------------------------------------------------------------
local user = "sharkingstudios"
local EVENT_YEAR = "2024"

-- Update Lua paths for local LuaRocks
package.path = package.path
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?.lua"
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?/init.lua"

package.cpath = package.cpath
  .. ";/home/" .. user .. "/.luarocks/lib/lua/5.3/?.so"

local json         = require("dkjson")
local http_request = require("http.request")
local lfs          = require("lfs")

------------------------------------------------------------------------------
-- 2. CSV Utility for Jobs
------------------------------------------------------------------------------
local function read_jobs_csv(filename)
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
    local fields = {}
    for field in string.gmatch(lines[i], "([^,]+)") do
      table.insert(fields, field)
    end
    local row = {}
    for idx, h in ipairs(headers) do
      row[h] = fields[idx] or ""
    end
    table.insert(rows, row)
  end
  return rows, headers
end

local function write_jobs_csv(filename, rows, headers)
  local file = io.open(filename, "w")
  if not file then
    return
  end
  file:write(table.concat(headers, ",") .. "\n")
  for _, row in ipairs(rows) do
    local line_parts = {}
    for _, h in ipairs(headers) do
      table.insert(line_parts, row[h] or "")
    end
    file:write(table.concat(line_parts, ",") .. "\n")
  end
  file:close()
end

local JOBS_CSV = "jobs.csv"

local function create_job(job_type, job_data_table, retry_count)
  local team_number = "N/A"
  if job_data_table and job_data_table.team_number then
    team_number = tostring(job_data_table.team_number)
  end

  print("Creating new job:", job_type, "for team number:", team_number)

  local rows, headers = read_jobs_csv(JOBS_CSV)

  -- Ensure the needed columns exist
  local needed_cols = {"job_id", "job_type", "status", "job_data", "created_at", "done_at", "retry_count"}
  local header_map = {}
  for _, h in ipairs(headers) do
    header_map[h] = true
  end
  for _, col in ipairs(needed_cols) do
    if not header_map[col] then
      table.insert(headers, col)
      header_map[col] = true
    end
  end

  local job_id
  local id_exists
  repeat
    job_id = tostring(math.random(100000, 999999))
    id_exists = false
    for _, row in ipairs(rows) do
      if row.job_id == job_id then
        id_exists = true
        break
      end
    end
  until not id_exists

  local new_job = {
    job_id = job_id,
    job_type = job_type,
    status = "queued",
    job_data = json.encode(job_data_table or {}),
    created_at = tostring(os.time()), -- Store as string
    done_at = "",
    retry_count = tostring(retry_count or 0)
  }
  table.insert(rows, new_job)
  write_jobs_csv(JOBS_CSV, rows, headers)

  print("Job created with ID:", job_id, "for team number:", team_number)

  return job_id
end


------------------------------------------------------------------------------
-- 3. Additional Utility Functions (for teams.csv, TBA fetch, Python call, etc.)
------------------------------------------------------------------------------

-- Utility to read teams.csv
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

local function read_teams_csv(filename)
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

local function write_teams_csv(filename, rows, headers)
  local file = io.open(filename, "w")
  if not file then
    return
  end

  file:write(table.concat(headers, ",") .. "\n")
  for _, row in ipairs(rows) do
    local parts = {}
    for _, h in ipairs(headers) do
      table.insert(parts, row[h] or "")
    end
    file:write(table.concat(parts, ",") .. "\n")
  end
  file:close()
end

-- Basic utility to check file existence
local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

------------------------------------------------------------------------------
-- 4. "fetch_team_data" logic (optional TBA calls), "save_to_csv", etc.
------------------------------------------------------------------------------
local function tba_get(path)
  local API_KEY = os.getenv("TBA_API_KEY") or ""
  local url = "https://www.thebluealliance.com/api/v3/" .. path
  local req = http_request.new_from_uri(url)
  req.headers:upsert(":method", "GET")
  req.headers:upsert("x-tba-auth-key", API_KEY)

  local headers, stream = req:go()
  if not headers then
    return nil, "TBA request failed"
  end

  local body = stream:get_body_as_string()
  stream:shutdown()
  return json.decode(body), nil
end

local function fetch_district_points(team_number)
  local districts, err = tba_get("team/frc" .. team_number .. "/districts")
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
  if type(team_info) == "table" then
    team_info = team_info[1] or team_info  -- handle possibility
  end
  if not team_info then return nil end

  local events = tba_get("team/frc" .. team_number .. "/events/" .. EVENT_YEAR)
  if not events or #events == 0 then
    return {
      team_number = team_number,
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
      goto continue
    end
    local status_info = tba_get("team/frc" .. team_number .. "/event/" .. ev.key .. "/status")
    if status_info and status_info.qual and status_info.qual.ranking then
      local q = status_info.qual.ranking
      local playoff = status_info.playoff
      local qRec = q.record or {}
      local pRec = (playoff and playoff.record) or {}

      local eventWins   = (qRec.wins   or 0) + (pRec.wins   or 0)
      local eventLosses = (qRec.losses or 0) + (pRec.losses or 0)
      local eventTies   = (qRec.ties   or 0) + (pRec.ties   or 0)

      if q.rank and q.rank < best_rank then
        best_rank = q.rank
      end
      total_wins   = total_wins   + eventWins
      total_losses = total_losses + eventLosses
      total_ties   = total_ties   + eventTies
    end
    ::continue::
  end

  local district_points = fetch_district_points(team_number)

  local combined = {
    team_number    = team_number,
    nickname       = team_info.nickname or "",
    city           = team_info.city or "",
    rookie_year    = team_info.rookie_year or 0,
    rank           = best_rank < 999999 and best_rank or 0,
    wins           = total_wins,
    losses         = total_losses,
    ties           = total_ties,
    ranking_points = district_points
  }

  return combined
end

-- Filter out blank fields from a table
local function filter_blank_fields(data)
  local filtered_data = {}
  for key, value in pairs(data) do
    if value ~= nil and value ~= "" then
      filtered_data[key] = value
    end
  end
  return filtered_data
end

local function save_to_csv(team_data)
  local filename = "teams.csv"
  local rows, headers = read_teams_csv(filename)

  local required_cols = {
    "team_number", "nickname", "last_updated", "city", "rookie_year",
    "rank", "wins", "losses", "ties", "ranking_points",
    "image_path", "image_x", "image_y", "image_zoom",
    "custom_label", "flavor_text", "abilities_list", "attacks_list",
    "hitpoints", "illustrator", "base_set", "supertype", "type_",
    "subtype", "variation", "rarity", "subname",
    "weakness_type", "weakness_amt", "resistance_type", "resistance_amt",
    "retreat_cost", "icon_text", "total_number_in_set", "custom_regulation_mark_image"
  }

  -- Ensure required columns exist
  local header_map = {}
  for _, h in ipairs(headers) do
    header_map[h] = true
  end
  for _, col in ipairs(required_cols) do
    if not header_map[col] then
      table.insert(headers, col)
      header_map[col] = true
    end
  end

  -- Update or add the row
  local row_map = {}
  for _, row in ipairs(rows) do
    row_map[row.team_number] = row
  end

  local key = tostring(team_data.team_number)
  local row = row_map[key]
  if not row then
    row = {}
    table.insert(rows, row)
  end

  for _, col in ipairs(required_cols) do
    row[col] = team_data[col] or row[col] or ""
  end

  write_teams_csv(filename, rows, headers)
end


-- Build card data for the Python service
local function build_card_data_from_csv(team_number)
  local rows, headers = read_teams_csv("teams.csv")
  for _, row in ipairs(rows) do
    if row.team_number == tostring(team_number) then
      local image_path = row.image_path
      if not image_path or image_path == "" then
        local png_path = "./images/robotImages/" .. row.team_number .. ".png"
        if file_exists(png_path) then
          image_path = png_path
        else
          local jpeg_path = "./images/robotImages/" .. row.team_number .. ".jpeg"
          if file_exists(jpeg_path) then
            image_path = jpeg_path
          else
            image_path = "./images/robotImages/default.png"
          end
        end
      end

      -- Build card data
      local card_data = {
        team_number = row.team_number,
        team_name = row.nickname or ("Team " .. row.team_number),
        image_path = image_path,
        image_x = tonumber(row.image_x),
        image_y = tonumber(row.image_y),
        image_zoom = tonumber(row.image_zoom),
        custom_label = row.custom_label,
        flavor_text = row.flavor_text,
        abilities_list = row.abilities_list and json.decode(row.abilities_list),
        attacks_list = row.attacks_list and json.decode(row.attacks_list),
        hitpoints = row.hitpoints,
        illustrator = row.illustrator,
        base_set = row.base_set,
        supertype = row.supertype,
        type_ = row.type_,
        subtype = row.subtype,
        variation = row.variation,
        rarity = row.rarity,
        subname = row.subname,
        weakness_type = row.weakness_type,
        weakness_amt = row.weakness_amt,
        resistance_type = row.resistance_type,
        resistance_amt = row.resistance_amt,
        retreat_cost = row.retreat_cost,
        icon_text = row.icon_text,
        total_number_in_set = row.total_number_in_set,
        custom_regulation_mark_image = row.custom_regulation_mark_image
      }

      -- Remove blank fields
      return filter_blank_fields(card_data)
    end
  end
  return nil
end

local function create_card_via_python(card_data)
  local req_body = json.encode(card_data)

  local req = http_request.new_from_uri("http://sharkingstudios.hackclub.app:8091/create-card")
  req.headers:upsert(":method", "POST")
  req.headers:upsert("content-type", "application/json")
  req:set_body(req_body)

  local headers, stream = req:go()
  if not headers then
    return false, "Failed to connect to python server"
  end

  local status = tonumber(headers:get(":status"))
  local response_body = stream:get_body_as_string()
  stream:shutdown()

  if status ~= 200 then
    print("Trying to create card again for team_number=", card_data.team_number)
    local success, result = pcall(create_job, "updateOneCard", { team_number = card_data.team_number })
    if not success then print("Error occurred: ", result) else print("Job probably created successfully: ", result) end
    return false, "Python server error: " .. tostring(status) .. " => " .. response_body
  end

  local resp_json = json.decode(response_body) or {}
  if resp_json.status == "success" then
    return true, resp_json.card_path
  else
    print("Trying to create card again for team_number=", card_data.team_number)
    local success, result = pcall(create_job, "updateOneCard", { team_number = card_data.team_number })
    if not success then print("Error occurred: ", result) else print("Job probably created successfully: ", result) end
    return false, resp_json.message or "Unknown card creation error \n Starting New Card Creation Job..."
  end
end

local function updateCardForTeam(team_number)
  -- Fetch data and update `teams.csv`
  local tba_data = fetch_team_data(team_number)
  if tba_data then
    tba_data.last_updated = os.time() -- Set last updated timestamp
    save_to_csv(tba_data) -- Save updated team data
  end

  -- Build card data and create the card
  local card_data = build_card_data_from_csv(team_number)
  if not card_data then
    return false, "Team not found in CSV or missing required fields"
  end

  local success, result = create_card_via_python(card_data)
  return success, result
end


------------------------------------------------------------------------------
-- 5. Actual Job Execution
------------------------------------------------------------------------------

local function do_update_one_card(team_number)
  print("Doing updateOneCard for team_number=", team_number)
  local success, msg = updateCardForTeam(team_number)
  return success, (msg or "")
end

local function do_update_all_cards()
  print("Doing updateAllCards...")
  -- Possibly read "teams.csv" and call updateCardForTeam for each row
  local all_rows, headers = read_teams_csv("teams.csv")
  local any_error = false
  -- local message = "All cards updated"
  local message = "Please dont use this lol. It breaks a lot."
  -- for _, row in ipairs(all_rows) do
  --   local team_number = row.team_number
  --   local s, m = updateCardForTeam(team_number)
  --   if not s then
  --     any_error = true
  --     message = "Error updating team " .. tostring(team_number) .. ": " .. m
  --     break
  --   end
  -- end
  -- return (not any_error), message
  return false, message
end

local function save_new_team_data(team_number)
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
  end
end

------------------------------------------------------------------------------
-- 6. Main "while true" loop to poll jobs.csv
------------------------------------------------------------------------------

while true do
  -- Read the latest state of the file
  local rows, headers = read_jobs_csv(JOBS_CSV)
  local changed = false
  local now = os.time()

  -- Track job IDs for quick lookup
  local job_ids = {}
  for _, row in ipairs(rows) do
    job_ids[row.job_id] = row
  end

  -- Process queued jobs
  for i, row in ipairs(rows) do
    if row.status == "queued" then
      -- Mark as running
      row.status = "running"
      row.created_at = tostring(os.time())
      changed = true

      -- Parse job data
      local job_data = json.decode(row.job_data) or {}
      local success, message = false, "unknown"

      if row.job_type == "updateOneCard" then
        local team_number = job_data.team_number
        success, message = do_update_one_card(team_number)
      elseif row.job_type == "updateAllCards" then
        success = false
        message = "Please dont use this lol. It breaks a lot."
      else
        success = false
        message = "Unknown job type"
      end

      -- Update status based on success
      if success then
        row.status = "OK"
        row.job_data = json.encode({ info = message })
      else
        row.status = "ERROR"
        row.job_data = json.encode({ error = message })
      end

      row.done_at = tostring(os.time())

      break -- Process one job at a time
    end
  end

  -- Remove old completed jobs (OK or ERROR) older than 5 minutes
  local new_rows = {}
  for _, row in ipairs(rows) do
    if row.status == "OK" or row.status == "ERROR" then
      local done_at = tonumber(row.done_at) or 0
      if done_at == 0 or (now - done_at) < 300 then
        table.insert(new_rows, row) -- Keep the row
      else
        changed = true -- Mark as changed since we are cleaning up
      end
    else
      table.insert(new_rows, row)
    end
  end

  if changed then
    -- Re-read the latest file and merge changes
    local latest_rows, _ = read_jobs_csv(JOBS_CSV)
    local latest_job_ids = {}
    for _, row in ipairs(latest_rows) do
      latest_job_ids[row.job_id] = row
    end

    -- Update `new_rows` to include any new jobs from the latest file
    for _, latest_row in ipairs(latest_rows) do
      if not job_ids[latest_row.job_id] then
        table.insert(new_rows, latest_row) -- Add new jobs
      end
    end

    -- Write back the updated state
    write_jobs_csv(JOBS_CSV, new_rows, headers)
  end

  os.execute("sleep 2")
end
