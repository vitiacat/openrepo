local component = require("component")
local event = require("event")
local shell = require("shell")
local fs = require('filesystem')
local thread = require('thread')
local rcc_utils = require('rcc_utils')
local sha256 = require('sha256')
local process = require('process')
local args, options = shell.parse(...)

local function getPath(str,sep)
    sep=sep or'/'
    return str:match("(.*"..sep..")")
end

local m = component.modem
local pPath = getPath(shell.resolve(process.info().path), '/')

print("Remote Computer Control Server v1 [by DesConnet and Vitiacat]\nPress Ctrl+C to exit (or rcc_server kill if server working in background)")

if options.debug then
    print('Path: ' .. pPath)
end

if not fs.exists(fs.concat(pPath, 'rcc/rcc.cfg')) then
    io.stderr:write('Config file "rcc.cfg" not found')
    os.exit()
elseif not fs.exists(fs.concat(pPath, 'rcc/rcc_users.cfg')) then
    io.stderr:write('Config file "rcc_users.cfg" not found')
    os.exit()
end

local users = rcc_utils.cfgParse(io.open(fs.concat(pPath, 'rcc/rcc_users.cfg'), 'r'))

if options.help then
    print('rcc_server users add/remove - add or remove user\nrcc_server kill - kill running server\nrcc_server --background - run server in background')
    return
end

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
            rcc_utils.cfgSave(users, fs.concat(pPath, 'rcc/rcc_users.cfg'))
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
            rcc_utils.cfgSave(users, fs.concat(pPath, 'rcc/rcc_users.cfg'))
            print('User with username "'..args[3]..'" has been removed.')
            os.exit()
        end
    end
    if args[1] == 'kill' then
        print('Killing server...')
        io.open(fs.concat(pPath, '/rcc/.exit'), 'w'):close()
        os.sleep(1)
        fs.remove(fs.concat(pPath, '/rcc/.exit'))
        print('Killed')
        return
    end
end

local function main()

    local config = rcc_utils.cfgParse(io.open(fs.concat(pPath, 'rcc/rcc.cfg'), 'r'))
    local blockedCommands = rcc_utils.Split(config.blockedCommands, ',')

    if m.isOpen(tonumber(config.port)) then
        io.stderr:write(string.format('Port %s is already open', config.port))
        return
    end

    if config.serverName:find(' ') then
        io.stderr:write('Server name includes invalid characters')
    end

    m.open(tonumber(config.port))

    local run = true
    local commands_directory = '/bin/'
    local current_directory = shell.getWorkingDirectory()
    local isSendingFile = false
    local connections = {}

    local latest_msg_id = 0

    local function send(address, id, message)
        m.send(address, tonumber(config.port), latest_msg_id .. ';' .. id .. ';' .. message)
        latest_msg_id = latest_msg_id + 1
    end

    local function onMessage(_, _, from, port, _, msg)
        if type(msg) ~= 'string' then
            do return end
        end

        --if port ~= config.port then return end

        --print('Send message: ' .. msg)

        local sp = rcc_utils.Split(msg, ' ')
        local command = sp[1]
        local args = ''
        for i = 2, #sp, 1 do
            args = args .. sp[i]
            if i ~= #sp then
                args = args .. ' '
            end
        end

        if command == 'rcc' then
            if sp[2] == nil then
                send(from, 4, 'subcommand is empty')
            end
            local subcommand = sp[2]

            if options.debug then
                print(string.format('Recived message: %s from %s', msg, from))
            end

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
                connections[from] = {username = username, isSendingFile = false, file = nil}
            --Authorization
            elseif subcommand == 'ping' then
                send(from, 3, 'ping')
            elseif subcommand == 'info' then
                local b ={ ["true"]=true, ["false"]=false }
                if not b[config.hideServer] then
                send(from, 3, string.format('info %s %s', config.serverName, m.address))
                end
            elseif subcommand == 'getCurrentDirectory' and connections[from] ~= nil  then
                send(from, 3, 'getCurrentDirectory' .. ' ' .. current_directory)
            elseif subcommand == 'sendFile' and connections[from] ~= nil then
                if not config.isSendingFileAllowed then
                    send(from, 4, 'File sending is disabled on this server')
                    do return end
                end
                connections[from].isSendingFile = true
                local path = getPath(sp[3], '/')
                if fs.exists(path) == false then
                    fs.makeDirectory(path)
                end
                connections[from].file = io.open(sp[3], 'w')
                send(from, 3, 'sendFile')
            elseif subcommand == 'endSendFile' and connections[from] ~= nil then
                connections[from].isSendingFile = false
                connections[from].file:close()
                send(from, 3, 'endSendFile')
            end
            do return end
        end

        if connections[from] == nil then
            send(from, 4, 'Unauthorized')
            do return end
        end

        if connections[from].isSendingFile then
            connections[from].file:write(msg)
            send(from, 1, '')
            do return end
        end

        if options.debug then print("Executed function: " .. tostring(msg)) end
        if rcc_utils.HasValue(blockedCommands, command) then
                send(from, 4, 'Command is blocked on this server')
                do return end
        elseif command == 'cd' then
            if #args == 0 then
                current_directory = '/home'
                shell.setWorkingDirectory(current_directory)
                send(from, 2, '')
                do return end
            end
            if not fs.isDirectory(args) then
                send(from, 4, 'Directory not found')
                do return end
            end
            current_directory = args
            shell.setWorkingDirectory(current_directory)
            send(from, 2, '')
        else
            if fs.exists(fs.concat(commands_directory, command .. '.lua')) or fs.exists(fs.concat(current_directory, command .. '.lua')) then
                local program = nil
                if fs.exists(fs.concat(commands_directory, command .. '.lua')) then
                    program = io.popen(fs.concat(commands_directory, command .. '.lua ' .. args), 'r')
                else
                    program = io.popen(fs.concat(current_directory, command .. '.lua ' .. args), 'r')
                end
                local result = ''
                for line in program:lines() do
                    result = result .. line .. '\n'
                end
                send(from, 2, result)
            else
                send(from, 4, 'File not found')
                do return end
            end

            do return end
        end
    --print(shell.execute(tostring(msg)))
    end

    if not options.background then
        event.listen('interrupted', function ()
            print('Closing...')
            run = false
        end)
    end

    event.listen('modem_message', onMessage)

    while run do
        if options.background then
            if fs.exists(fs.concat(pPath, '/rcc/.exit')) then
                fs.remove(fs.concat(pPath, '/rcc/.exit'))
                run = false
            end
        end
        if options.background then
            os.sleep(5)
        else
            os.sleep(1)
        end
    end

    m.close(tonumber(config.port))
    event.ignore('modem_message', onMessage)
    print('Bye!')

end

if options.background then
    thread.create(function () main() end):detach()
else
    main()
end