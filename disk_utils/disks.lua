local component = require('component')
local disks = {}

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

for address in component.list("filesystem") do
	local proxy = component.proxy(address)
	table.insert(disks, proxy)
end

for _, disk in ipairs(disks) do
	print(string.format('%s - %s (%s/%s)', disk.address, (disk.getLabel() or '<without label>'), bytesToSize(disk.spaceUsed()), bytesToSize(disk.spaceTotal())))
end
