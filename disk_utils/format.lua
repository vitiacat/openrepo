local fs = require('filesystem')
local shell = require('shell')
local inspect = require('inspect')
local args, options = shell.parse(...)
if args[1] == nil then
	print('Usage: format [drive UUID (3 chars)/drive label]')
	os.exit()
end
local disk = fs.proxy(args[1])
if disk == nil then
	print('Drive not found.')
end
print(disk.address .. ' - ' .. (disk.getLabel() or '<without label>'))
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
		-- format the drive
	for index, name in ipairs(disk.list('/')) do
		print('Removing /' .. name)
		disk.remove('/' .. name)
	end
	print('Drive formatted succesfully.')

else
	print('Cancelled')
end