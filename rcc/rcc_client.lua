local component = require('component')
local modem = component.modem
local event = require('event')
local term = require('term')
local shell = require('shell')
local fs = require('filesystem')
local thread = require('thread')
local sha256 = require('sha256')

local args, options = shell.parse(...)
local port = tonumber(options.port) or 369

if options.help then
    print('rcc_client [--debug] [--port=369]\nrcc_client upload [file path]')
    os.exit()
end

print('Remote Computer Control Client v1 [by DesConnet and Vitiacat]\nFinding servers...')
modem.open(port)

local server_answered = true
local time = 0
local is_pinged = false
local is_logged = false
local readyToSendFile = false
local continueSendFile = true
local current_directory = '/home'
local continue = true
local latest_msg_id = nil
local server_address = ''
local servers = {}

local function split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local function onMessage(_, _, from, port, _, message)
    local sp = split(message, ';')
    local uid = tonumber(sp[1])
    local id = sp[2]

    if is_logged then
        if latest_msg_id == nil then
            latest_msg_id = uid
        else
            if latest_msg_id >= uid then
                do return end
            end
            latest_msg_id = uid
        end
    end

    if options.debug then
        print(message)
    end

    local text = ''
    for i = 3, #sp, 1 do
        text = text .. sp[i]
    end

    -- id = 1 - ping, 2 - command answer, 3 - rcc answers, 4 - error --
    if id == '2' then
        modem.send(server_address, port, 'rcc getCurrentDirectory')
        continue = false
        server_answered = true
        os.sleep(0.3)
        if text ~= '' then print(text) end
        continue = true
    elseif id == '3' then
        local arr = split(text, ' ')
        if arr[1] == 'getCurrentDirectory' then
            local name = ''
            for i = 2, #arr, 1 do
                name = name .. arr[i]
            end
            current_directory = name
        elseif arr[1] == 'ping' then
            is_pinged = true
        elseif arr[1] == 'sendFile' then
            readyToSendFile = true
        elseif arr[1] == 'login' then
            if arr[2] == 'ok' then
                is_logged = true
            else
                io.stderr:write('Login failed\n')
                is_logged = 2
            end
        elseif arr[1] == 'info' then
            local contains = false
            for _, server in ipairs(servers) do
                if server.address == arr[3] then
                    contains = true
                    break
                end
            end
            if not contains then table.insert(servers, {name = arr[2], address = arr[3]}) end
        end
    elseif id == '4' then
        io.stderr:write(text .. '\n')
        server_answered = true
        if args[1] == 'upload' then
            os.exit()
        end
    elseif id == '1' then
        continueSendFile = true
    end

end

event.listen('modem_message', onMessage)

modem.broadcast(port, 'rcc info')

while time < 2.5 do
    time = time + 0.1
    os.sleep(0.1)
end

local text = ''

if #servers == 0 then
    print('No servers found ;-;')
    return
end

if #servers ~= 1 then

    for i, server in ipairs(servers) do
        text = string.format('%s[ %s ] %s - %s\n', text, i, server.name, server.address)
    end

    print(text)
    io.write('Select server: ')
    local select = io.read()
    select = tonumber(select)
    if not select then
        print('Incorrect input')
        os.exit()
    end
    if #servers < select or select < 1 then
        print('Incorrect input')
        os.exit()
    end
    server_address = servers[select].address
else
    server_address = servers[1].address
end

print('Connecting...')

-- check if server is live
modem.send(server_address, port, 'rcc ping')
while not is_pinged do
    time = time + 0.1
    modem.send(server_address, port, 'rcc ping')
    if time > 5 then
        io.stderr:write('Can\'t connect to server.\n')
        os.exit()
    end
    os.sleep(0.1)
end

os.sleep(0.5)
time = 0

io.write('Username: ')
local username = io.read()
io.write('Password: ')
local password = io.read()
modem.send(server_address, port, 'rcc login ' .. username .. ' ' .. sha256(password))
while not is_logged do
    time = time + 0.1
    if time > 5 then
        io.stderr:write('Login timeout.')
        os.exit()
    end
    os.sleep(0.1)
end

if is_logged == 2 then
    os.exit()
end

print('Connected.')
time = 0

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

local function sendFile(path)
    local i = 0
    if not fs.exists(path) then
        io.stderr:write('File not found.')
        os.exit()
    end
    local file = io.open(path, "r")
    local size = fs.size(path)
    local read = 0
    local _, y = term.getCursor()
    modem.send(server_address, port, 'rcc sendFile ' ..  path)
    while(not readyToSendFile) do
        os.sleep(0.1)
    end
    local cancelled = false
    local bytes = ''
    local sendedBytes = 0
    local t = thread.create(function ()
        term.setCursor(1, y + 1)
        term.write('Press Ctrl + C to cancel upload')
        local value = event.pull('interrupted')
        cancelled = true
        term.setCursor(1, y + 1)
        term.clearLine()
        print('Wait...')
    end)
    local t2 = thread.create(function ()
        while not cancelled do
            os.sleep(1)
            sendedBytes = 0
        end
    end)
    while read < size and not cancelled do
        bytes = file:read(1024)
        if bytes ~= nil then
            read = read + #bytes
            sendedBytes = sendedBytes + #bytes
        end
        continueSendFile = false
        time = 0
        while(not continueSendFile) do
            if time >= 3 then
                cancelled = true
                break
            end
            os.sleep(0.05)
            modem.send(server_address, port, bytes)
            time = time + 0.05
        end
        if not cancelled then
            term.setCursor(1, y)
            term.clearLine()
            term.write(string.format('Sending file... Sended %s of %s (%.2f %%), avg time: %.1f sec', bytesToSize(read), bytesToSize(size), read/size * 100, (size - read) / 8000))
        end
    end
    if cancelled then
        os.sleep(1)
        modem.send(server_address, port, 'rcc cancelSendFile')
        term.setCursor(1, y + 2)
        if time >= 2.5 then
            print('File sent timeout')
        else
            print('File sent cancelled')
        end
        os.exit()
    end
    t:kill()
    t2:kill()
    term.setCursor(1, y + 2)
    os.sleep(1)
    modem.send(server_address, port, 'rcc endSendFile')
    print('File has been sent.')
    os.exit()
end

local function listenCommands()
    event.listen('interrupted', function ()
        text = 'exit'
        os.exit()
    end)
    print('Press Ctrl + C or type exit to exit.')
    while (text ~= 'exit') do
        if server_answered == false then
            os.sleep(0.1)
            time = time + 0.1
            if time > 5
            then 
                io.stderr:write('Server did\'nt answer after five seconds.')
                break
            end
        else 
            if continue ~= true then
                os.sleep(0.1)
            else
                io.write('\27[32m' .. current_directory .. '\27[37m' .. ' \27[31m> \27[37m')
                text = io.read()
                if text ~= '' then
                    if text == 'clear' then
                        term.clear()
                    end
                    modem.send(server_address, port, text)
                    server_answered = false
                end
            end
        end
    end
end

if args[1] ~= nil then
    if args[1] == 'upload' then
        if args[2] == nil then
            print('rcc_client upload [file path]')
            os.exit()
        end
        sendFile(args[2])
    end
end

listenCommands()

event.ignore('modem_message', onMessage)