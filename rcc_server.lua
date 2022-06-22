local component = require("component")
local event = require("event")
local shell = require("shell")
local fs = require('filesystem')
local process = require('process')
local inspect = require('inspect')


if component.modem == nil then
    print('This program requires modem.')
    os.exit()
end

local m = component.modem
print("Remote Computer Control Server v1 [by DesConnet and Vitiacat]")
m.open(369)

local run = true
local commands_directory = '/bin/'
local current_directory = shell.getWorkingDirectory()
local isSendingFile = false
local file = nil

local function split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local latest_msg_id = 0

local function send(address, id, message)
    m.send(address, 369, latest_msg_id .. ';' .. id .. ';' .. message)
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

    print('Send message: ' .. msg)

    local sp = split(msg, ' ')
    local command = sp[1]
    local args = ''
    for i = 2, #sp, 1 do
        args = args .. sp[i] .. ' '
    end

    if command == 'exit' then
        run = false
        do return end
    end

    if command == 'rcc' then
        if sp[2] == nil then
            send(from, 4, 'subcommand is empty')
        end
        local subcommand = sp[2]

        if subcommand == 'getCurrentDirectory' then
            send(from, 3, 'getCurrentDirectory' .. ' ' .. current_directory)
        elseif subcommand == 'ping' then
            send(from, 3, 'ping')
        elseif subcommand == 'sendFile' then
            isSendingFile = true
            local path = getPath(sp[3], '/')
            if fs.exists(path) == false then
                fs.makeDirectory(path)
            end
            file = io.open(sp[3], 'w')
            send(from, 3, 'sendFile')
        elseif subcommand == 'endSendFile' then
            isSendingFile = false
            file:close()
            send(from, 3, 'endSendFile')
        end
        do return end
    end

    if isSendingFile then
        file:write(msg)
        send(from, 1, '')
        do return end
    end

    print("Executed function: " .. tostring(msg))
    if command == 'cd' then
        current_directory = args
        shell.setWorkingDirectory(current_directory)
        send(from, 2, 'OK')
    else
        print(current_directory)
        if fs.exists(commands_directory .. '/' .. command .. '.lua') then
            local program = io.popen(commands_directory .. '/' .. command .. '.lua ' .. args, 'r')
            local result = ''
            for line in program:lines() do
                result = result .. line .. '\n'
            end
            send(from, 2, result)
        else
            print('Program ' .. command .. ' not exists')
            send(from, 4, 'Program not exists')
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
