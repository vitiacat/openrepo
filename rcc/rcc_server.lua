local component = require("component")
local event = require("event")
local shell = require("shell")
local fs = require('filesystem')
local process = require('process')
local rcc_utils = require('rcc_utils')
local sha256 = require('sha256')
local args = shell.parse(...)

local m = component.modem

print("Remote Computer Control Server v1 [by DesConnet and Vitiacat]")

if not fs.exists(fs.concat(shell.getWorkingDirectory(), 'rcc.cfg')) then
    io.stderr:write('Config file "rcc.cfg" not found')
    os.exit()
elseif not fs.exists(fs.concat(shell.getWorkingDirectory(), 'rcc_users.cfg')) then
    io.stderr:write('Config file "rcc_users.cfg" not found')
    os.exit()
end

local users = rcc_utils.cfgParse(io.open('rcc_users.cfg', 'r'))

if args[1] ~= nil then
    if args[1] == 'users' then
        if args[2] == nil then
            print('Usage: rcc_server users add/remove')
            os.exit()
        elseif args[2] == 'add' then
            if args[3] == nil or args[4] == nil then
                print('Usage: rcc_server users add [username] [password]')
                os.exit()
            end
            if users[args[3]] ~= nil then
                io.stderr:write('User exists')
                os.exit()
            end
            users[args[3]] = sha256(args[4])
            rcc_utils.cfgSave(users, 'rcc_users.cfg')
            print('User with username "'..args[3]..'" has been created.')
            os.exit()
        elseif args[2] == 'remove' then
            if args[3] == nil then
                print('Usage: rcc_server users remove [username]')
                os.exit()
            end
            if users[args[3]] == nil then
                io.stderr:write('User not found')
                os.exit()
            end
            users[args[3]] = nil
            rcc_utils.cfgSave(users, 'rcc_users.cfg')
            print('User with username "'..args[3]..'" has been removed.')
            os.exit()
        end
    end
end

local config = rcc_utils.cfgParse(io.open('rcc.cfg', 'r'))
local blockedCommands = rcc_utils.Split(config.blockedCommands, ',')

m.open(tonumber(config.port))

local run = true
local commands_directory = '/bin/'
local current_directory = shell.getWorkingDirectory()
local isSendingFile = false
local file = nil
local connections = {}

local latest_msg_id = 0

local function send(address, id, message)
    m.send(address, tonumber(config.port), latest_msg_id .. ';' .. id .. ';' .. message)
    latest_msg_id = latest_msg_id + 1
end

local function getPath(str,sep)
    sep=sep or'/'
    return str:match("(.*"..sep..")")
end

local function onMessage(_, _, from, port, _, msg)
    if type(msg) ~= 'string' then
        do return end
    end

    --print('Send message: ' .. msg)

    local sp = rcc_utils.Split(msg, ' ')
    local command = sp[1]
    local args = ''
    for i = 2, #sp, 1 do
        args = args .. sp[i] .. ' '
    end

    if command == 'rcc' then
        if sp[2] == nil then
            send(from, 4, 'subcommand is empty')
        end
        local subcommand = sp[2]

        --Authorization
        if subcommand == 'login' then
            local username = sp[3]
            local password = sp[4]
            if users[username] == nil then
                send(from, 3, 'login fail')
                do return end
            end
            if users[username] ~= password then
                send(from, 3, 'login fail')
                do return end
            end
            send(from, 3, 'login ok')
            connections[from] = username
        --Authorization
        elseif subcommand == 'ping' then
            send(from, 3, 'ping')
        elseif subcommand == 'getCurrentDirectory' and connections[from] ~= nil  then
            send(from, 3, 'getCurrentDirectory' .. ' ' .. current_directory)
        elseif subcommand == 'sendFile' and connections[from] ~= nil then
            if not config.isSendingFileAllowed then
                send(from, 4, 'File sending is disabled on this server')
                do return end
            end
            isSendingFile = true
            local path = getPath(sp[3], '/')
            if fs.exists(path) == false then
                fs.makeDirectory(path)
            end
            file = io.open(sp[3], 'w')
            send(from, 3, 'sendFile')
        elseif subcommand == 'endSendFile' and connections[from] ~= nil then
            isSendingFile = false
            file:close()
            send(from, 3, 'endSendFile')
        end
        do return end
    end

    if connections[from] == nil then
        send(from, 4, 'Unauthorized')
        do return end
    end

    if isSendingFile then
        file:write(msg)
        send(from, 1, '')
        do return end
    end

    print("Executed function: " .. tostring(msg))
    if rcc_utils.HasValue(blockedCommands, command) then
            send(from, 4, 'Command is blocked on this server')
            do return end
    elseif command == 'cd' then
        current_directory = args
        shell.setWorkingDirectory(current_directory)
        send(from, 2, 'OK')
    else
        if fs.exists(commands_directory .. '/' .. command .. '.lua') then
            local program = io.popen(commands_directory .. '/' .. command .. '.lua ' .. args, 'r')
            local result = ''
            for line in program:lines() do
                result = result .. line .. '\n'
            end
            send(from, 2, result)
        else
            send(from, 4, 'Program don\'t exists')
            do return end
        end

        do return end
    end
--print(shell.execute(tostring(msg)))
end

while run
do
 onMessage(event.pull('modem_message'))
 os.sleep(0.1)
end
