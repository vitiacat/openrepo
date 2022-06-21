local fs = require('filesystem')
local shell = require('shell')
local inspect = require('inspect')
local args, options = shell.parse(...)
print(inspect(args))
print(args[1])
local disk = fs.proxy(args[1])
if disk == nil then
	print('Drive not found.')
end
print(disk.address .. ' - ' .. (disk.getLabel() or ' <without label>'))
print('Are you sure want to format this drive? y/n')
local answer = io.read()
if answer == 'y' or answer == 'yes' or answer == 'Y' then
	io.write('Write a new label for this drive (leave blank for empty): ')
	local label = io.read()
	if not label then
		print('Cancelled')
		os.exit()
	end
	if label == '' then label = nil end
	disk.setLabel(label)
	for index, name in ipairs(disk.list('/')) do
		print('Removing /' .. name)
		disk.remove('/' .. name)
	end
	print('Drive formated.')
	-- format the drive

else
	print('Cancelled')
end