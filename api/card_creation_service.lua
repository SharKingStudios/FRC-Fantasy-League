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
local csv          = require("lua-csv.csv")

------------------------------------------------------------------------------
-- 2. CSV Utility for Jobs
------------------------------------------------------------------------------
-- local function parse_csv_line(line)
--   local fields = {}
--   local pattern = '("([^"]*)"|[^,]+)'
--   for part, quoted in string.gmatch(line, pattern) do
--     if quoted then
--       -- part is quoted => quoted is what's inside
--       -- Convert doubled quotes ("") to single quote (")
--       local unescaped = quoted:gsub('""', '"')
--       table.insert(fields, unescaped)
--     else
--       -- unquoted field
--       table.insert(fields, part)
--     end
--   end
--   return fields
-- end

local function to_csv_line(fields)
  local pieces = {}
  for _, val in ipairs(fields) do
    val = tostring(val or "")
    -- double up any " inside val
    val = val:gsub('"', '""')
    -- wrap in quotes
    val = '"' .. val .. '"'
    table.insert(pieces, val)
  end
  return table.concat(pieces, ",")
end

function parse_csv_line(line)
  local res = {}
  local pos = 1
  while true do
    -- Quoted field?
    if string.sub(line, pos, pos) == '"' then
      local txt = ""
      local startPos = pos
      pos = pos + 1
      while true do
        local c = string.sub(line, pos, pos)
        if c == '"' then
          -- Look ahead for another quote
          if string.sub(line, pos+1, pos+1) == '"' then
            -- It's an escaped quote
            txt = txt .. '"'
            pos = pos + 2
          else
            -- Reached the end of the quoted field
            pos = pos + 1
            break
          end
        else
          txt = txt .. c
          pos = pos + 1
        end
      end
      table.insert(res, txt)
      -- Skip past comma
      while string.sub(line, pos, pos) == ' ' do
        pos = pos + 1
      end
      if string.sub(line, pos, pos) == ',' then
        pos = pos + 1
      end
    else
      -- Unquoted field
      local startPos = pos
      while string.sub(line, pos, pos) ~= '' and
            string.sub(line, pos, pos) ~= ',' do
        pos = pos + 1
      end
      table.insert(res, string.sub(line, startPos, pos - 1))
      -- Skip the comma
      if string.sub(line, pos, pos) == ',' then
        pos = pos + 1
      end
    end
    if string.sub(line, pos, pos) == '' then
      break
    end
  end
  return res
end

local jobs_headers = {
  "job_id", "job_type", "status", "job_data", "created_at", "done_at", "retry_count"
}
local teams_headers = {
  "team_number", "nickname", "last_updated", "city", "rookie_year",
  "rank", "wins", "losses", "ties", "ranking_points", "image_x", "image_y", "image_zoom",
  "custom_label", "flavor_text", "abilities_list", "attacks_list",
  "hitpoints", "illustrator", "base_set", "supertype", "type_",
  "subtype", "variation", "rarity", "subname",
  "weakness_type", "weakness_amt", "resistance_type", "resistance_amt",
  "retreat_cost", "icon_text", "total_number_in_set", "custom_regulation_mark_image"
}

local function read_csv(filename)
  -- Determine the appropriate headers based on the file name
  local known_headers
  if filename == "jobs.csv" then
    known_headers = jobs_headers
  elseif filename == "teams.csv" then
    known_headers = teams_headers
  else
    error("Unknown CSV file: " .. filename)
  end

  -- Open the file
  local f = io.open(filename, "r")
  if not f then
    return {}, known_headers -- Return empty rows with headers
  end

  -- Read and discard the first line (assumed to be the header)
  f:read("*l")

  -- Prepare a table for the rows
  local rows = {}

  -- Read remaining lines manually and parse them into rows
  for line in f:lines() do
    line = line:gsub("\r", "")
    local fields = parse_csv_line(line) -- Use your custom parse_csv_line
    -- print("DEBUG: Parsed fields =>", json.encode(fields))
    
    if #fields ~= #known_headers then
      error("Row field count does not match header count in file: " .. filename ..
            ". Fields: " .. json.encode(fields) .. " Headers: " .. json.encode(known_headers))
    end

    local row = {}
    for i, field in ipairs(fields) do
      row[known_headers[i]] = field -- Map fields to known headers
    end
    table.insert(rows, row)
  end

  -- Close the file
  f:close()

  -- Debug output
  -- print("DEBUG: rows =>", json.encode(rows))
  return rows, known_headers
end




local function write_jobs_csv(filename, rows, headers)
  local file = io.open(filename, "w")
  if not file then
    return
  end
  -- Write header line
  file:write(table.concat(headers, ",") .. "\n")
  -- Write each row
  for _, row in ipairs(rows) do
    local fields = {}
    for _, h in ipairs(headers) do
      table.insert(fields, row[h] or "")
    end
    file:write(to_csv_line(fields) .. "\n")
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

  local rows, headers = read_csv(JOBS_CSV)

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

local function write_csv(filename, rows, headers)
  local f = io.open(filename, "w")
  if not f then
    return nil, "Cannot open file: " .. filename
  end

  -- You can instantiate a csv 'writer' but typically you'd do something like:
  -- Write out the header line first:
  f:write(table.concat(headers, ",") .. "\n")

  -- Then write each row
  for _, row in ipairs(rows) do
    local fields = {}
    for _, h in ipairs(headers) do
      local val = row[h] or ""
      -- Escape quotes per CSV spec (same as your old to_csv_line logic)
      val = val:gsub('"', '""')
      val = '"' .. val .. '"'
      table.insert(fields, val)
    end
    f:write(table.concat(fields, ",") .. "\n")
  end

  f:close()
  return true
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

function read_teams_csv(filename)
  local f = io.open(filename, "r")
  if not f then
    -- Return empty tables if file missing
    return {}, {}
  end

  local reader = csv.open(f, { headers = true })
  local rows = {}
  for fields in reader:lines() do
    -- fields is a table keyed by header
    table.insert(rows, fields)
  end
  f:close()

  -- Gather headers from the first row (if available)
  local headers = {}
  if #rows > 0 then
    -- rows[1] is like { team_number = "1771", nickname="North Gwinnett Robotics", ... }
    for colName, _ in pairs(rows[1]) do
      table.insert(headers, colName)
    end
    -- NOTE: pairs() doesn't guarantee a stable order if you need a specific ordering
  end

  return rows, headers
end


function write_teams_csv(filename, rows, headers)
  -- Open the file for writing
  local f = io.open(filename, "w")
  if not f then
    return nil, "Cannot open file: " .. filename
  end

  table.sort(rows, function(a, b)
    local rpA = tonumber(a.ranking_points) or 0
    local rpB = tonumber(b.ranking_points) or 0
    return rpA > rpB
  end)
  
  -- 3. Reassign 'rank' from 1..N
  for i, row in ipairs(rows) do
    row.rank = i
  end

  -- Write headers as a row
  f:write(table.concat(headers, ",") .. "\n")

  -- Write each row
  for _, row in ipairs(rows) do
    local line = {}
    for _, h in ipairs(headers) do
      local val = tostring(row[h] or "") -- Ensure val is a string
      -- Escape quotes and wrap in quotes per CSV spec
      val = '"' .. val:gsub('"', '""') .. '"'
      table.insert(line, val)
    end
    f:write(table.concat(line, ",") .. "\n")
  end

  -- Close the file
  f:close()
  return true
end


-- Basic utility to check file existence
local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function downscale_images_if_idle()--jobs)
  -- First, see if there are any active jobs (queued or running).
  -- If so, we do nothing.
  -- local has_active = false
  -- for _, job in ipairs(jobs) do
  --   if job.status == "queued" or job.status == "running" then
  --     has_active = true
  --     break
  --   end
  -- end

  -- -- Only proceed if NO active jobs
  -- if has_active then
  --   return
  -- end

  -- Paths
  local user = "sharkingstudios"
  local base_dir = "/home/"..user.."/frcfantasyserver/FRC-Fantasy-League/api/robotCards"
  local size220_dir = base_dir .. "/size220"

  -- Make sure the size220 directory exists
  lfs.mkdir(size220_dir)

  for file in lfs.dir(base_dir) do
    -- We only want to look at image files (png, jpg, jpeg, possibly others)
    if file:match("%.png$") or file:match("%.jpg$") or file:match("%.jpeg$") then
      local from_path = base_dir .. "/" .. file
      local to_path   = size220_dir .. "/" .. file
      
      -- Check if we already have a 220px version
      if not file_exists(to_path) then
        print("No 220px version found for " .. file .. ". Creating it now.")
        -- Use mogrify to resize to width=220, saving the output in size220_dir
        -- The -path argument tells mogrify where to put the converted file
        local cmd = string.format("mogrify -resize 220 -path '%s' '%s'", size220_dir, from_path)
        os.execute(cmd)
      end
    end
  end
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

local function fetch_team_data_new(team_number)
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
  local rows, headers = read_csv(filename)

  local required_cols = {
    "team_number", "nickname", "last_updated", "city", "rookie_year",
    "rank", "wins", "losses", "ties", "ranking_points", "image_x", "image_y", "image_zoom",
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

local function save_to_csv_new(team_data)
  local filename = "teams.csv"
  local rows, headers = read_csv(filename)

  local required_cols = {
    "team_number", "nickname", "last_updated", "city", "rookie_year",
    "rank", "wins", "losses", "ties", "ranking_points", "image_x", "image_y", "image_zoom",
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
  local rows, headers = read_csv("teams.csv")
  for _, row in ipairs(rows) do
    if row.team_number == tostring(team_number) then
      -- local image_path = row.image_path

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

      if image_path == "./images/robotImages/default.png" then
        print("No image found for team_number=", team_number)
        row.image_x = 0
        row.image_y = -80
        row.image_zoom = 0.6
      end

      local custom_label
      if row.custom_label == "" then
        custom_label = row.nickname or ("No. " .. row.team_number .. " FRC")
      else
        custom_label = row.custom_label
      end

      -- Build card data
      local card_data = {
        team_number = row.team_number,
        team_name = row.nickname or ("Team " .. row.team_number),
        image_path = image_path,
        image_x = tonumber(row.image_x),
        image_y = tonumber(row.image_y),
        image_zoom = tonumber(row.image_zoom),
        custom_label = custom_label,
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
  
  
  local rows, headers = read_csv("teams.csv")
  local team_exists = false
  for _, row in ipairs(rows) do
    if row.team_number == tostring(team_number) then team_exists = true end
  end
  
  if not team_exists then
    local tba_data = fetch_team_data(team_number)
    if tba_data then
      tba_data.last_updated = os.time() -- Set last updated timestamp
      save_to_csv(tba_data) -- Save updated team data
    end
  else
    local tba_data = fetch_team_data_new(team_number)
    if tba_data then
      tba_data.last_updated = os.time() -- Set last updated timestamp
      save_to_csv_new(tba_data) -- Save updated team data
    end
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
  local all_rows, headers = read_csv("teams.csv")
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
  local rows, headers = read_csv(JOBS_CSV)
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

      -- print("DEBUG: raw job_data =>", row.job_data)
      if not job_data.team_number then
        -- print("DEBUG: json.decode failed or team_number missing!")
      else
        -- print("DEBUG: team_number =>", job_data.team_number)
      end

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
        os.execute("rm /home/sharkingstudios/frcfantasyserver/FRC-Fantasy-League/api/robotCards/size220/"..job_data.team_number..".png")
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
    local latest_rows, _ = read_csv(JOBS_CSV)
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

  downscale_images_if_idle()

  os.execute("sleep 2")
end
