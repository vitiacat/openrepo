local component = require('component')
local fs = require('filesystem')
local inspect = require('inspect')
local disks = {}

function bytesToSize(bytes)
  kilobyte = 1024;
  megabyte = kilobyte * 1024;

  if((bytes >= 0) and (bytes < kilobyte)) then
    return bytes .. " bytes";
  elseif((bytes >= kilobyte) and (bytes < megabyte)) then
    return bytes / kilobyte .. ' KB';
  elseif((bytes >= megabyte)) then
    return bytes / megabyte .. ' MB';
  end
end

for address in component.list("filesystem") do
	local proxy = component.proxy(address)
	table.insert(disks, proxy)
end

for _, disk in ipairs(disks) do
	print(disk.address .. ' - ' .. (disk.getLabel() or '<without label>')
	 .. ' ' .. bytesToSize(disk.spaceUsed()) .. '/' .. bytesToSize(disk.spaceTotal()))
end
