-- card_creation_service.lua
-- Continuously polls "jobs.csv" for queued/running jobs, executes them, updates their status & data.

-- Update Lua paths for local LuaRocks
package.path = package.path
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?.lua"
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?/init.lua"

package.cpath = package.cpath
  .. ";/home/" .. user .. "/.luarocks/lib/lua/5.3/?.so"

local json = require("dkjson")
local http_request = require("http.request")
local lfs = require("lfs")

-- Reuse the CSV logic from server.lua or replicate it here
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

-- Example: do "updateOneCard"
local function do_update_one_card(team_number)
  -- put your TBA fetch or call your python server, etc.
  print("Doing updateOneCard for team_number=", team_number)
  -- e.g. success = true/false, message = "some error or info"
  local success = true
  local message = "Card updated for team " .. tostring(team_number)
  return success, message
end

-- Example: do "updateAllCards"
local function do_update_all_cards()
  print("Doing updateAllCards...")
  -- same pattern, loop or do your big TBA calls
  local success = true
  local message = "All cards updated!"
  return success, message
end

-- Convert status from queued => running => done
-- We'll say if it's "queued", we set "running", do the job, then set "OK" or "ERROR".
while true do
  local rows, headers = read_jobs_csv(JOBS_CSV)
  local changed = false

  for i, row in ipairs(rows) do
    if row.status == "queued" then
      -- Mark "running"
      row.status = "running"
      changed = true

      -- parse row.job_data => table
      local job_data = {}
      if row.job_data and row.job_data ~= "" then
        job_data = json.decode(row.job_data) or {}
      end

      local success, message = false, "unknown"

      if row.job_type == "updateOneCard" then
        local team_number = job_data.team_number
        success, message = do_update_one_card(team_number)

      elseif row.job_type == "updateAllCards" then
        success, message = do_update_all_cards()

      else
        -- unknown job type
        success = false
        message = "Unknown job_type: " .. tostring(row.job_type)
      end

      if success then
        row.status = "OK"
        -- optionally store message in row.job_data as well
        row.job_data = json.encode({ info = message })
      else
        row.status = "ERROR"
        row.job_data = json.encode({ error = message })
      end

      break -- handle one job at a time, then rewrite CSV
    end
  end

  if changed then
    write_jobs_csv(JOBS_CSV, rows, headers)
  end

  -- Sleep a bit before checking again
  os.execute("sleep 2")
end
