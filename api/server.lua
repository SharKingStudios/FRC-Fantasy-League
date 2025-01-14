-- server.lua
local user = "sharkingstudios"
local EVENT_YEAR = "2024"

-- Update Lua paths for local LuaRocks
package.path = package.path
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?.lua"
  .. ";/home/" .. user .. "/.luarocks/share/lua/5.3/?/init.lua"

package.cpath = package.cpath
  .. ";/home/" .. user .. "/.luarocks/lib/lua/5.3/?.so"

local socket = require("socket")
local json = require("dkjson")
local lfs = require("lfs")  -- or omit if not needed
local http_request = require("http.request")


-- ==========================
-- Folders & Setup
-- ==========================
local cards_folder = "./robotCards"
if not lfs.attributes(cards_folder, "mode") then
  lfs.mkdir(cards_folder)
end

local robot_images_folder = "./robotImages"
if not lfs.attributes(robot_images_folder, "mode") then
  lfs.mkdir(robot_images_folder)
end

local USERS_CSV = "users.csv"

-- Ensure users.csv has a proper header if it doesn't exist
do
  local file = io.open(USERS_CSV, "r")
  if not file then
    local f = io.open(USERS_CSV, "w")
    if f then
      -- EXACT columns: "username,password_hash,session_token,cards_owned,money"
      f:write("username,password_hash,session_token,cards_owned,money\n")
      f:close()
    end
  else
    file:close()
  end
end


-- CSV utilities for jobs
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

  -- Assume the first line is headers: job_id,job_type,status,job_data
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

-- Make sure there's a header row if the file doesn't exist
do
  local file = io.open(JOBS_CSV, "r")
  if not file then
    local f = io.open(JOBS_CSV, "w")
    if f then
      f:write("job_id,job_type,status,job_data\n")
      f:close()
    end
  else
    file:close()
  end
end

-- Utility: create a new job row
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
-- 0. Utilities for users.csv
-- ==========================

local function read_users_csv(filename)
  local file = io.open(filename, "r")
  if not file then return {}, {} end

  local lines = {}
  for line in file:lines() do
    line = line:match("^%s*(.-)%s*$")  -- trim whitespace
    if line ~= "" then                -- skip empty lines
      table.insert(lines, line)
    end
  end
  file:close()

  if #lines == 0 then return {}, {} end

  local headers = {}
  for h in string.gmatch(lines[1], "([^,]+)") do
    table.insert(headers, h)
  end

  local rows = {}
  for i=2, #lines do
    local fields = {}
    for f in string.gmatch(lines[i], "([^,]+)") do
      table.insert(fields, f)
    end

    local row = {}
    for idx, hdr in ipairs(headers) do
      row[hdr] = fields[idx] or ""
    end
    table.insert(rows, row)
  end

  return rows, headers
end

local function write_users_csv(filename, rows, headers)
  local file = io.open(filename, "w")
  if not file then return end

  -- Write the header line EXACTLY once
  file:write(table.concat(headers, ",") .. "\n")

  for _, row in ipairs(rows) do
    -- build line in correct order
    local lineParts = {}
    for _, h in ipairs(headers) do
      lineParts[#lineParts+1] = row[h] or ""
    end
    file:write(table.concat(lineParts, ",") .. "\n")
  end

  file:close()
end


-- trivial hash function (not secure!)
local function simple_hash(str)
  -- you'd want to do real hashing, e.g. with an external library
  local sum = 0
  for i=1,#str do
    sum = (sum + str:byte(i)) % 65535
  end
  return tostring(sum)
end

-- find user by token
local function find_user_by_token(token)
  local rows, headers = read_users_csv(USERS_CSV)
  for _, row in ipairs(rows) do
    if row.session_token == token then
      return row, rows, headers
    end
  end
  return nil, rows, headers
end

local function write_csv(filename, rows, headers)
  local file = io.open(filename, "w")
  if not file then return end

  -- Write headers
  file:write(table.concat(headers, ",") .. "\n")

  -- Write rows
  for _, row in ipairs(rows) do
    local line = {}
    for _, header in ipairs(headers) do
      table.insert(line, row[header] or "")
    end
    file:write(table.concat(line, ",") .. "\n")
  end

  file:close()
end

-- Function to add unique headers to an existing list
local function add_unique_headers(existing_headers, new_headers)
  local header_set = {}
  -- Add existing headers to a set for quick lookup
  for _, header in ipairs(existing_headers) do
    header_set[header] = true
  end
  -- Add new headers if they don't already exist
  for _, header in ipairs(new_headers) do
    if not header_set[header] then
      table.insert(existing_headers, header)
      header_set[header] = true
    end
  end
  return existing_headers
end

local function updateTeamsCSV(req, res)
  local body = req.body
  local data = json.decode(body)

  if not data or not data.updatedRows or not data.headers then
    return res:status(400):json({ error = "Invalid request format" })
  end

  -- Read existing teams.csv
  local teamsFile = "teams.csv"
  local rows, headers = read_csv(teamsFile)

  -- Ensure headers are updated without duplication
  headers = add_unique_headers(headers, data.headers)

  -- Update rows or add new ones
  for _, updatedRow in ipairs(data.updatedRows) do
    local found = false
    for _, row in ipairs(rows) do
      if row.team_number == updatedRow.team_number then
        for key, value in pairs(updatedRow) do
          row[key] = value
        end
        found = true
        break
      end
    end

    if not found then
      table.insert(rows, updatedRow)
    end
  end

  -- Write back to teams.csv
  write_csv(teamsFile, rows, headers)
  return res:status(200):json({ message = "Teams CSV updated successfully." })
end


local function parse_headers(client)
  local headers = {}
  while true do
    local line = client:receive()
    if not line or line == "" then break end -- End of headers
    local key, value = line:match("^(.-):%s*(.+)$")
    if key and value then
      headers[key:lower()] = value -- Store headers as lowercase keys for consistency
    end
  end
  return headers
end


-------------------------------------------------------------------------------
-- Minimal HTTP server for incoming requests
-------------------------------------------------------------------------------
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
      local new_job = create_job("updateOneCard", { team_number = team_number })
      if new_job then
        client:send("HTTP/1.1 200 OK\r\n\r\nTeam data saved.\n")
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nFailed to fetch team data.\n")
      end

    elseif method == "GET" and path == "/api/teams.csv" then
      -- Serve teams.csv directly
      local file = io.open("teams.csv", "r")
      if file then
        local contents = file:read("*a")
        file:close()
        client:send("HTTP/1.1 200 OK\r\nContent-Type: text/csv\r\n\r\n" .. contents)
      else
        client:send("HTTP/1.1 404 Not Found\r\n\r\n")
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

    --------------------------------------------------------------------------
    -- CREATE ASYNC JOBS
    --------------------------------------------------------------------------
    elseif method == "POST" and path == "/api/admin/asyncUpdateAllCards" then
      -- We'll queue a job called "updateAllCards"
      local job_id = create_job("updateAllCards", {})
      local resp_body = json.encode({ status = "accepted", job_id = job_id })
      local response = "HTTP/1.1 202 Accepted\r\nContent-Type: application/json\r\n\r\n" .. resp_body
      client:send(response)

    elseif method == "POST" and path:match("^/api/admin/asyncUpdateCard/") then
      local tnum = path:match("^/api/admin/asyncUpdateCard/(%d+)$")
      if tnum then
        -- We'll queue a job called "updateOneCard" with job_data = {team_number=tnum}
        local job_id = create_job("updateOneCard", { team_number = tnum })
        local resp_body = json.encode({ status = "accepted", job_id = job_id })
        local response = "HTTP/1.1 202 Accepted\r\nContent-Type: application/json\r\n\r\n" .. resp_body
        client:send(response)
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing or invalid team number.\n")
      end

    --------------------------------------------------------------------------
    -- Check Job Status
    --------------------------------------------------------------------------
    elseif method == "GET" and path:match("^/api/admin/jobStatus/") then
      local j_id = path:match("^/api/admin/jobStatus/(%d+)$")
      if j_id then
        local rows, headers = read_jobs_csv(JOBS_CSV)
        local found = false
        for _, row in ipairs(rows) do
          if row.job_id == j_id then
            found = true
            local status = row.status
            local created_at = tonumber(row.created_at) or 0
            local done_at    = tonumber(row.done_at)    or 0
    
            local run_time = 0
            if status == "queued" or status == "running" then
              -- still ongoing => run_time is now - created_at
              run_time = os.time() - created_at
            else
              -- status is "OK" or "ERROR" => use done_at - created_at
              if done_at > 0 then
                run_time = done_at - created_at
              else
                -- fallback if for some reason done_at not set
                run_time = os.time() - created_at
              end
            end
    
            if status == "queued" or status == "running" then
              local resp = {
                status = "running",
                run_time = run_time,
              }
              local resp_json = json.encode(resp)
              client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp_json)
    
            elseif status == "OK" then
              -- row.job_data might have info
              local detail = row.job_data or ""
              local resp = {
                status = "OK",
                detail = detail,
                run_time = run_time
              }
              local resp_json = json.encode(resp)
              client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp_json)
    
            elseif status == "ERROR" then
              local detail = row.job_data or ""
              local resp = {
                status = "ERROR",
                detail = detail,
                run_time = run_time
              }
              local resp_json = json.encode(resp)
              client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp_json)
    
            else
              -- unknown
              local resp = {
                status = status,
                run_time = run_time
              }
              local resp_json = json.encode(resp)
              client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp_json)
            end
            break
          end
        end
        if not found then
          client:send("HTTP/1.1 404 Not Found\r\n\r\nInvalid job id.\n")
        end
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing or invalid job id.\n")
      end
  
    --------------------------------------------------------------------------
    -- The Big Kahuna: Uploading an image file
    --------------------------------------------------------------------------
    elseif method == "POST" and path == "/api/admin/uploadRobotImage" then
      --------------------------------------------------------------------------
      -- 1. Read HTTP headers and content length
      --------------------------------------------------------------------------
      local content_length = 0
      local content_type = nil
      local request_headers = {}
      repeat
        local header_line = client:receive()
        if not header_line or header_line == "" then break end
        table.insert(request_headers, header_line)
    
        local cl = header_line:match("^Content%-Length:%s*(%d+)")
        if cl then
          content_length = tonumber(cl) or 0
        end
    
        local ct = header_line:match("^Content%-Type:%s*(.+)$")
        if ct then
          content_type = ct
        end
      until false
    
      if not content_type or not content_type:find("multipart/form%-data;") then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing or invalid Content-Type (multipart/form-data required).\n")
        goto done_upload
      end
    
      -- Extract boundary from Content-Type: multipart/form-data; boundary=XXXX
      local boundary = content_type:match("boundary=(.+)")
      if not boundary then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nBoundary not found in Content-Type.\n")
        goto done_upload
      end
    
      --------------------------------------------------------------------------
      -- 2. Read the POST body fully
      --------------------------------------------------------------------------
      local raw_body = client:receive(content_length)
      if not raw_body then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nFailed to read request body.\n")
        goto done_upload
      end
    
      -- We'll add "--" for boundary splitting logic
      boundary = "--" .. boundary
    
      --------------------------------------------------------------------------
      -- 3. Split the body by the boundary
      --------------------------------------------------------------------------
      local parts = {}
      for part in raw_body:gmatch("(.-)" .. boundary) do
        table.insert(parts, part)
      end
      -- The last split might contain extra trailing lines after final boundary
    
      -- We'll store form fields:
      local teamNumber = nil
      local fileContent = nil
      local fileName = nil  -- e.g. "someimage.png"
    
      --------------------------------------------------------------------------
      -- 4. Parse each part, look for "teamNumber" or "robotImage"
      --------------------------------------------------------------------------
      for _, partData in ipairs(parts) do
        -- skip if empty or just newline
        if #partData > 0 then
          -- Try to separate headers from the data
          local headerSection, bodySection = partData:match("^(.-\r?\n\r?\n)(.*)")
          if headerSection and bodySection then
            -- Check for name=, filename=, etc.
            local dispLine = headerSection:match("Content%-Disposition:%s*form%-data;.-\r?\n")
            if dispLine then
              local fieldName = dispLine:match('name="([^"]+)"')
              local fileParam = dispLine:match('filename="([^"]+)"')
    
              if fieldName == "teamNumber" and not fileParam then
                -- This part is just the text field for teamNumber
                local val = bodySection:gsub("\r?\n$", "")  -- remove trailing newline
                teamNumber = val
    
              elseif fieldName == "robotImage" and fileParam then
                -- This is the file upload
                fileName = fileParam
                -- bodySection might contain the entire binary data
                -- remove trailing newlines if they exist
                fileContent = bodySection:match("^(.*)\r?\n?$")
              end
            end
          end
        end
      end
    
      --------------------------------------------------------------------------
      -- 5. Validate + Save the image file
      --------------------------------------------------------------------------
      if not teamNumber or not fileContent or not fileName then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing teamNumber or file data.\n")
        goto done_upload
      end
    
      -- We only support .png or .jpeg
      local ext = nil
      if fileName:lower():match("%.png$") then
        ext = "png"
      elseif fileName:lower():match("%.jpe?g$") then
        ext = "jpeg"
      else
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nOnly .png or .jpeg files are supported.\n")
        goto done_upload
      end
    
      local outputPath = "./images/robotImages/" .. teamNumber .. "." .. ext
      local outFile = io.open(outputPath, "wb")
      if not outFile then
        client:send("HTTP/1.1 500 Internal Server Error\r\n\r\nFailed to open output file.\n")
        goto done_upload
      end
      outFile:write(fileContent)
      outFile:close()

      local job_id = create_job("updateOneCard", { team_number = teamNumber })
    
      client:send("HTTP/1.1 200 OK\r\n\r\nFile uploaded successfully as " .. outputPath .. "\n")
    
      ::done_upload::

    elseif method == "GET" and path == "/api/admin/jobs.csv" then
      -- Serve jobs.csv directly
      local file = io.open("jobs.csv", "r")
      if file then
        local contents = file:read("*a")
        file:close()
        client:send("HTTP/1.1 200 OK\r\nContent-Type: text/csv\r\n\r\n" .. contents)
      else
        client:send("HTTP/1.1 404 Not Found\r\n\r\n")
      end
    
      local resp_json = json.encode(jobList)
      local response = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: application/json\r\n\r\n"
        .. resp_json
      client:send(response)

    elseif method == "POST" and path == "/api/admin/updateTeamsCSV" then
      local headers = parse_headers(client)
      local content_length = tonumber(headers["content-length"]) -- Parse Content-Length header
    
      if content_length then
        local body = client:receive(content_length)
        local success, result = pcall(function()
          return updateTeamsCSV({ body = body }, {
            status = function(_, code)
              return {
                code = code,
                json = function(_, obj)
                  local json_resp = json.encode(obj)
                  return "HTTP/1.1 " .. code .. " OK\r\nContent-Type: application/json\r\n\r\n" .. json_resp
                end
              }
            end
          })
        end)
        if success then
          client:send(result)
        else
          print("Error in updateTeamsCSV:", result)
          client:send("HTTP/1.1 500 Internal Server Error\r\n\r\nFailed to update teams.csv\n")
        end
      else
        print("Missing or invalid Content-Length header")
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nInvalid request.\n")
      end
    
    
    

    elseif method == "POST" and path == "/api/register" then
      -- parse content-length, read JSON => { username, password }
      -- ensure user not exist, store hashed pass
      local content_length = 0
      repeat
        local line = client:receive()
        if not line or line == "" then break end
        local cl = line:match("^Content%-Length:%s*(%d+)")
        if cl then content_length = tonumber(cl) end
      until false
      local body = client:receive(content_length)
      local data = json.decode(body or "{}")
      local uname = data.username
      local pword = data.password
      if not uname or not pword then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing fields.\n")
      else
        local rows, headers = read_users_csv(USERS_CSV)
        for _, row in ipairs(rows) do
          if row.username == uname then
            client:send("HTTP/1.1 400 Bad Request\r\n\r\nUsername already exists.\n")
            goto doneReg
          end
        end
        local newRow = {
          username = uname,
          password_hash = simple_hash(pword),
          session_token = "",
          cards_owned = "", -- no cards
          money = "20000"    -- give them some starting money
        }
        table.insert(rows, newRow)
        write_users_csv(USERS_CSV, rows, headers)
        client:send("HTTP/1.1 200 OK\r\n\r\nRegistered.\n")
        ::doneReg::
      end

    elseif method == "POST" and path == "/api/login" then
      local content_length = 0
      repeat
        local line = client:receive()
        if not line or line == "" then break end
        local cl = line:match("^Content%-Length:%s*(%d+)")
        if cl then content_length = tonumber(cl) end
      until false
      local body = client:receive(content_length)
      local data = json.decode(body or "{}")
      local uname = data.username
      local pword = data.password
      if not uname or not pword then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nMissing fields.\n")
      else
        local rows, headers = read_users_csv(USERS_CSV)
        local found = false
        for _, row in ipairs(rows) do
          if row.username == uname then
            found = true
            if row.password_hash == simple_hash(pword) then
              -- create session token
              local token = tostring(math.random(1,999999999)) -- naive
              row.session_token = token
              write_users_csv(USERS_CSV, rows, headers)
              local resp = json.encode({ session_token = token })
              client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp)
            else
              client:send("HTTP/1.1 401 Unauthorized\r\n\r\nInvalid password.\n")
            end
            break
          end
        end
        if not found then
          client:send("HTTP/1.1 401 Unauthorized\r\n\r\nUser not found.\n")
        end
      end

    elseif method == "GET" and path:match("^/api/logout") then
      -- parse ?token= from path
      local token = path:match("token=(%w+)")
      if not token then
        client:send("HTTP/1.1 400 Bad Request\r\n\r\nNo token param.\n")
      else
        local user, allRows, allHeaders = find_user_by_token(token)
        if user then
          user.session_token = ""
          write_users_csv(USERS_CSV, allRows, allHeaders)
          client:send("HTTP/1.1 200 OK\r\n\r\nLogged out.\n")
        else
          client:send("HTTP/1.1 400 Bad Request\r\n\r\nInvalid token.\n")
        end
      end

    elseif method == "GET" and path:match("^/api/user/inventory") then
      -- parse token
      local token = path:match("token=(%w+)")
      if not token then
        client:send("HTTP/1.1 401 Unauthorized\r\n\r\nNo token.\n")
      else
        local user = find_user_by_token(token)
        if not user then
          client:send("HTTP/1.1 401 Unauthorized\r\n\r\nInvalid session.\n")
        else
          local cards_str = user.cards_owned or ""
          if cards_str == "" then
            client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n[]")
          else
            local arr = {}
            for c in cards_str:gmatch("[^,]+") do table.insert(arr, c) end
            local resp = json.encode(arr)
            client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp)
          end
        end
      end

    elseif method == "GET" and path == "/api/market/top" then
      -- hardcode some top selling cards
      local topCards = {
        {team_number="1771"},
        {team_number="1261"},
        {team_number="1683"},
        {team_number="1771"},
        {team_number="1261"},
        {team_number="1683"}
      }
      local resp = json.encode(topCards)
      client:send("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. resp)
    
    else
      client:send("HTTP/1.1 404 Not Found\r\n\r\n")
    end
  end

  client:close()
end
