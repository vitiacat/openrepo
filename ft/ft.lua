--- json decode https://github.com/rxi/json.lua ---
local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do
      res[ select(i, ...) ] = true
    end
    return res
  end
  local space_chars   = create_set(" ", "\t", "\r", "\n")
  local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
  local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
  local escape_char_map = {
    [ "\\" ] = "\\",
    [ "\"" ] = "\"",
    [ "\b" ] = "b",
    [ "\f" ] = "f",
    [ "\n" ] = "n",
    [ "\r" ] = "r",
    [ "\t" ] = "t",
  }
  local escape_char_map_inv = { [ "/" ] = "/" }
  for k, v in pairs(escape_char_map) do
    escape_char_map_inv[v] = k
  end
  local literals      = create_set("true", "false", "null")
  local literal_map = {
    [ "true"  ] = true,
    [ "false" ] = false,
    [ "null"  ] = nil,
  }
  local function next_char(str, idx, set, negate)
    for i = idx, #str do
      if set[str:sub(i, i)] ~= negate then
        return i
      end
    end
    return #str + 1
  end
  local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
      col_count = col_count + 1
      if str:sub(i, i) == "\n" then
        line_count = line_count + 1
        col_count = 1
      end
    end
    error( string.format("%s at line %d col %d", msg, line_count, col_count) )
  end
  local function codepoint_to_utf8(n)
    local f = math.floor
    if n <= 0x7f then
      return string.char(n)
    elseif n <= 0x7ff then
      return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then
      return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
    elseif n <= 0x10ffff then
      return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                         f(n % 4096 / 64) + 128, n % 64 + 128)
    end
    error( string.format("invalid unicode codepoint '%x'", n) )
  end
  local function parse_unicode_escape(s)
    local n1 = tonumber( s:sub(1, 4),  16 )
    local n2 = tonumber( s:sub(7, 10), 16 )
    if n2 then
      return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
      return codepoint_to_utf8(n1)
    end
  end
  local function parse_string(str, i)
    local res = ""
    local j = i + 1
    local k = j
  
    while j <= #str do
      local x = str:byte(j)
  
      if x < 32 then
        decode_error(str, j, "control character in string")
  
      elseif x == 92 then -- `\`: Escape
        res = res .. str:sub(k, j - 1)
        j = j + 1
        local c = str:sub(j, j)
        if c == "u" then
          local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                   or str:match("^%x%x%x%x", j + 1)
                   or decode_error(str, j - 1, "invalid unicode escape in string")
          res = res .. parse_unicode_escape(hex)
          j = j + #hex
        else
          if not escape_chars[c] then
            decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
          end
          res = res .. escape_char_map_inv[c]
        end
        k = j + 1
  
      elseif x == 34 then -- `"`: End of string
        res = res .. str:sub(k, j - 1)
        return res, j + 1
      end
  
      j = j + 1
    end
  
    decode_error(str, i, "expected closing quote for string")
  end
  local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then
      decode_error(str, i, "invalid number '" .. s .. "'")
    end
    return n, x
  end
  local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
      decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
  end
  local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
      local x
      i = next_char(str, i, space_chars, true)
      -- Empty / end of array?
      if str:sub(i, i) == "]" then
        i = i + 1
        break
      end
      -- Read token
      x, i = parse(str, i)
      res[n] = x
      n = n + 1
      -- Next token
      i = next_char(str, i, space_chars, true)
      local chr = str:sub(i, i)
      i = i + 1
      if chr == "]" then break end
      if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
  end
  local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
      local key, val
      i = next_char(str, i, space_chars, true)
      -- Empty / end of object?
      if str:sub(i, i) == "}" then
        i = i + 1
        break
      end
      -- Read key
      if str:sub(i, i) ~= '"' then
        decode_error(str, i, "expected string for key")
      end
      key, i = parse(str, i)
      -- Read ':' delimiter
      i = next_char(str, i, space_chars, true)
      if str:sub(i, i) ~= ":" then
        decode_error(str, i, "expected ':' after key")
      end
      i = next_char(str, i + 1, space_chars, true)
      -- Read value
      val, i = parse(str, i)
      -- Set
      res[key] = val
      -- Next token
      i = next_char(str, i, space_chars, true)
      local chr = str:sub(i, i)
      i = i + 1
      if chr == "}" then break end
      if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
  end
  local char_func_map = {
    [ '"' ] = parse_string,
    [ "0" ] = parse_number,
    [ "1" ] = parse_number,
    [ "2" ] = parse_number,
    [ "3" ] = parse_number,
    [ "4" ] = parse_number,
    [ "5" ] = parse_number,
    [ "6" ] = parse_number,
    [ "7" ] = parse_number,
    [ "8" ] = parse_number,
    [ "9" ] = parse_number,
    [ "-" ] = parse_number,
    [ "t" ] = parse_literal,
    [ "f" ] = parse_literal,
    [ "n" ] = parse_literal,
    [ "[" ] = parse_array,
    [ "{" ] = parse_object,
  }
parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then
      return f(str, idx)
    end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
  end
  local function json_decode(str)
    if type(str) ~= "string" then
      error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then
      decode_error(str, idx, "trailing garbage")
    end
    return res
  end

--- end json parser ---

local internet = require('internet')
local term = require('term')
local shell = require('shell')
local fs = require('filesystem')
local unicode = require('unicode')
local computer = require('computer')

local args = shell.parse(...)

if #args < 2 then
    print('Usage: ft upload/download [path/ID]')
    return
end

local function create(filename, content)
    local boundary = '7686858'
    local data = ([[
--%s
Content-Disposition: form-data; name="file"; filename="%s"
Content-Type: application/octet-stream

%s
--%s--
    ]]):format(boundary, filename, content, boundary)
    return data, {['Cache-Control'] = 'no-cache', ['Content-Length'] = unicode.len(data), ['Connection'] = 'keep-alive', ['User-Agent'] = 'Mozilla/5.0 (X11; Linux x86_64; rv:6.0) Gecko/20210714 Firefox/37.0', ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary, ['Cookie'] = 'user_token=d64c9c19729541b3077b'}
end

local function upload(path)
    local file = io.open(path, 'r')
    local content = ''
    while true do
        local a = file:read()
        if a == nil then
            break
        end
        if a ~= '' then content = content .. a end
    end
    file:close()
    local data, headers = create(path:match("^.+/(.+)$"), content)
    local req = internet.request('https://ft.vitiacat.ru/upload.php', data, headers, 'POST')
    local res = ''
    local _, y = term.getCursor()
    local time = 0
    local result = ''
    while not req.finishConnect() do
        time = time + 0.1
        os.sleep(0.1)
        term.setCursor(1, y)
        term.clearLine()
        term.write(string.format('Sending file: elapsed %s s', time))
    end
    while res ~= nil do
        res = req.read()
        if res ~= nil and res ~= '' then
            result = result .. res
        end
    end
    term.setCursor(1, y)
    term.clearLine()
    result = json_decode(result)
    if result['error'] then
        term.write('Upload failed (server sent an error) :(')
    else
        term.write(string.format('File uploaded. URL: %s, ID: %s', result['url'], result['url']:match("^.+/(.+)$")))
    end
end

local function download(id, path)

    local function bytesToSize(bytes)
        local kilobyte = 1024;
        local megabyte = kilobyte * 1024;
      
        if((bytes >= 0) and (bytes < kilobyte)) then
          return bytes .. " bytes";
        elseif((bytes >= kilobyte) and (bytes < megabyte)) then
          return string.format('%.1f KiB', bytes / kilobyte);
        elseif((bytes >= megabyte)) then
          return string.format('%.1f MiB', bytes / megabyte);
        end
    end

    local file, reason = io.open(path, 'w')
    if file == nil then
        io.stderr:write(reason)
        return
    end
    local req = internet.request('https://ft.vitiacat.ru/download.php?id=' .. id, nil, {['Cache-Control'] = 'no-cache', ['Connection'] = 'keep-alive', ['User-Agent'] = 'Mozilla/5.0 (X11; Linux x86_64; rv:6.0) Gecko/20210714 Firefox/37.0'})
    local _, y = term.getCursor()
    local time = 0
    while req.finishConnect() == false do
        time = time + 0.1
        os.sleep(0.1)
        term.setCursor(1, y)
        term.clearLine()
        term.write(string.format('Downloading file: elapsed %s s', time))
    end
    local err, reason = req.finishConnect()
    if err == nil then
        io.stderr:write('\nDownloading error. Maybe file not found?')
        return
    end

    time = computer.uptime()
    local read = 0
    local _, _, headers = req.response()
    local size = tonumber(headers['Content-Length'][1])
    while true do
        local res, err = req.read()
        if not res then
            file:close()
            if read >= size then break end
            io.stderr:write('\n' .. err)
            break
        end

        term.setCursor(1, y)
        term.clearLine()
        term.write(string.format('Writing file: elapsed %.0f s, writed %s of %s', computer.uptime() - time, bytesToSize(read), bytesToSize(size)))
        file:write(res)
        read = read + #res
        os.sleep(0)
    end
    print('\nFile downloaded')
end

if args[1] == 'upload' then
    if not fs.exists(args[2]) or fs.isDirectory(args[2]) then
        io.stderr:write('File not found\n')
    end
    upload(args[2])
elseif args[1] == 'download' then
    if #args < 3 then
        print('Usage: ft download [ID] [path]')
        return
    end
    download(args[2], args[3])
else
    print('Usage: ft upload/download [path/ID] (download path)')
end
