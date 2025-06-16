-- Transplant by Lienol

module("luci.model.ethinfo", package.seeall)

local nxo = require "nixio"
local nfs = require "nixio.fs"
local jsc = require "luci.jsonc"
local uname = nxo.uname()

function getBuiltinEthernetPorts()
	local boardinfo = jsc.parse(nfs.readfile("/etc/board.json") or "")
	local ports = {}
	if type(boardinfo) == "table" and type(boardinfo.network) == "table" then
		for name, layout in pairs(boardinfo.network) do
			if name == "lan" or name == "wan" then
				if type(layout.ports) == "table" then
					for i, ifname in ipairs(layout.ports) do
						ports[#ports + 1] = {
							role = name,
							device = ifname
						}
					end
				elseif type(layout.device) == "string" then
					ports[#ports + 1] = {
						role = name,
						device = layout.device
					}
				end
			end
		end
		-- Workaround for targets that do not enumerate  all netdevs in board.json
		if uname.machine == "x86_64" and #ports > 0 and ports[1].device:match("^eth%d+$") then
			local bus = nfs.readlink(string.format("/sys/class/net/%s/device/subsystem", ports[1].device))
			function test(args)
				if not args.netdev:match("^eth%d+$") then
					return
				end
				if true then
					local length = 0
					for _, port in ipairs(args.ports) do
						if port.device == args.netdev then
							length = length + 1
						end
					end
					if length > 0 then
						return
					end
				end
				if nfs.readlink(string.format("/sys/class/net/%s/device/subsystem", args.netdev)) ~= bus then
					return
				end
				ports[#ports + 1] = {
					role = 'unknown',
					device = args.netdev
				}
			end
			for netdev, _ in nfs.dir("/sys/class/net") do
				test({netdev = netdev, ports = ports})
			end
		end
	end
	table.sort(ports, function(a, b)
		return a.device < b.device
	end)
	return ports
end

function getPortStats(portdev)
	local result = {}
	if portdev and nfs.access(string.format("/sys/class/net/%s", portdev)) then
		result["carrier"] = nfs.readfile(string.format("/sys/class/net/%s/carrier", portdev))
		result["duplex"] = nfs.readfile(string.format("/sys/class/net/%s/duplex", portdev))
		result["speed"] = nfs.readfile(string.format("/sys/class/net/%s/speed", portdev))
		for key, _ in nfs.dir(string.format("/sys/class/net/%s/statistics", portdev)) or {} do
			result[key] = nfs.readfile(string.format("/sys/class/net/%s/statistics/%s", portdev, key))
		end
		for k, v in pairs(result) do
			result[k] = v:match("^%s*(.-)%s*$")
		end
	end
	return result
end

function getAllInfo()
	local ports = getBuiltinEthernetPorts()
	for i, layout in ipairs(ports) do
		local stats = getPortStats(layout.device)
		layout.stats = stats
	end
	return ports
end
