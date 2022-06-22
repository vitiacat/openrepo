local component = require('component')
local modem = component.modem
local event = require('event')
local term = require('term')
local shell = require('shell')
local fs = require('filesystem')

local args, options = shell.parse(...)

if options.help then
    print('rcc_client [--debug]')
    os.exit()
end

print('Remote Computer Control Client v1\nConnecting...')

modem.open(369)

local server_answered = true
local time = 0
local is_pinged = false
local readyToSendFile = false
local continueSendFile = true
local current_directory = '/home'
local text = ''
local continue = true
local latest_msg_id = nil

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

    if latest_msg_id == nil then
        latest_msg_id = uid
    else
        if latest_msg_id >= uid then
            do return end
        end
        latest_msg_id = uid
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
        continue = false
        server_answered = true
        os.sleep(0.3)
        print(text)
        modem.broadcast(369, 'rcc getCurrentDirectory')
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
        end
    elseif id == '4' then
        io.stderr:write(text .. '\n')
        server_answered = true
    elseif id == '1' then
        continueSendFile = true
    end

end

event.listen('modem_message', onMessage)

-- check if server is live
modem.broadcast(369, 'rcc ping')
while not is_pinged do
    time = time + 0.1
    os.sleep(0.1)
    if time > 5 then
        io.stderr:write('Can\'t connect to server.')
        os.exit()
    end
end

os.sleep(1)

print('Connected.')
time = 0

local function bytesToSize(bytes)
    local kilobyte = 1024;
    local megabyte = kilobyte * 1024;
  
    if((bytes >= 0) and (bytes < kilobyte)) then
      return bytes .. " bytes";
    elseif((bytes >= kilobyte) and (bytes < megabyte)) then
      return math.ceil(bytes / kilobyte) .. ' KB';
    elseif((bytes >= megabyte)) then
      return math.ceil(bytes / megabyte) .. ' MB';
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
    modem.broadcast(369, 'rcc sendFile ' ..  path)
    while(not readyToSendFile) do
        os.sleep(0.1)
    end
    local bytes = ''
    while read < size do
        bytes = file:read(3000)
        print(read .. ' - ' .. size)
        if bytes ~= nil then
            read = read + #bytes
        end
        continueSendFile = false
        while(not continueSendFile) do
            os.sleep(0.05)
            modem.broadcast(369, bytes)
        end
        term.setCursor(1, y + 1)
        term.write(string.format('Sending file... Sended %s of %s ', bytesToSize(read), bytesToSize(size)))
    end
    term.setCursor(1, y + 2)
    os.sleep(1)
    local datas = {}
    for address, name in component.list("data", true) do
        table.insert(datas, component.proxy(address))
    end
    --local hash = ''
    --if #datas == 0 then
    --    print('\27[33mWARN: Data Card is not installed! Couldn\'t get file hash and verify it. ;-;\27[37m')
    --else
    --    file:seek("set")
    --    hash = component.invoke(datas[0], "md5", file:read(size))
    --end
    --print(hash)
    modem.broadcast(369, 'rcc endSendFile ')
    print('File has been sent.')
    os.exit()
end

local function listenCommands()
    while (text ~= 'exit') do
        if server_answered == false then
            os.sleep(0.1)
            time = time + 0.1
            if time > 5
            then 
                io.stderr:write('Server did\'nt answered after five seconds.')
                break
            end
        else 
            if continue ~= true then
                os.sleep(0.1)
            else
                io.write('\27[32m' .. current_directory .. '\27[37m' .. ' \27[31m> \27[37m')
                text = io.read()
                if text ~= '' then
                    modem.broadcast(369, text)
                    server_answered = false
                end
            end
        end
    end
end

if args[1] ~= nil then
    if args[1] == 'file' then
        if args[2] == nil then
            print('rcc_client file [path]')
            os.exit()
        end
        sendFile(args[2])
    end
end

listenCommands()

event.ignore('modem_message', onMessage)