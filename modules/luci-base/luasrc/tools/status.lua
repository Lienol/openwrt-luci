-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.tools.status", package.seeall)

local uci = require "luci.model.uci".cursor()
local i18n = require "luci.i18n"
has_iwinfo = pcall(require, "iwinfo")

local function dhcp_leases_common(family)
	local rv = { }
	local nfs = require "nixio.fs"
	local leasefile = "/tmp/dhcp.leases"

	uci:foreach("dhcp", "dnsmasq",
		function(s)
			if s.leasefile and nfs.access(s.leasefile) then
				leasefile = s.leasefile
				return false
			end
		end)

	local fd = io.open(leasefile, "r")
	if fd then
		while true do
			local ln = fd:read("*l")
			if not ln then
				break
			else
				local ts, mac, ip, name, duid = ln:match("^(%d+) (%S+) (%S+) (%S+) (%S+)")
				local expire = tonumber(ts) or 0
				if ts and mac and ip and name and duid then
					if family == 4 and not ip:match(":") then
						rv[#rv+1] = {
							expires  = (expire ~= 0) and os.difftime(expire, os.time()),
							macaddr  = mac,
							ipaddr   = ip,
							hostname = (name ~= "*") and name
						}
					elseif family == 6 and ip:match(":") then
						rv[#rv+1] = {
							expires  = (expire ~= 0) and os.difftime(expire, os.time()),
							ip6addr  = ip,
							duid     = (duid ~= "*") and duid,
							hostname = (name ~= "*") and name
						}
					end
				end
			end
		end
		fd:close()
	end

	local lease6file = "/tmp/hosts/odhcpd"
	uci:foreach("dhcp", "odhcpd",
		function(t)
			if t.leasefile and nfs.access(t.leasefile) then
				lease6file = t.leasefile
				return false
			end
		end)
	local fd = io.open(lease6file, "r")
	if fd then
		while true do
			local ln = fd:read("*l")
			if not ln then
				break
			else
				local iface, duid, iaid, name, ts, id, length, ip = ln:match("^# (%S+) (%S+) (%S+) (%S+) (-?%d+) (%S+) (%S+) (.*)")
				local expire = tonumber(ts) or 0
				if ip and iaid ~= "ipv4" and family == 6 then
					rv[#rv+1] = {
						expires  = (expire >= 0) and os.difftime(expire, os.time()),
						duid     = duid,
						ip6addr  = ip,
						hostname = (name ~= "-") and name
					}
				elseif ip and iaid == "ipv4" and family == 4 then
					local mac, mac1, mac2, mac3, mac4, mac5, mac6
					if duid and type(duid) == "string" then
						 mac1, mac2, mac3, mac4, mac5, mac6 = duid:match("^(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)$")
					end
					if not (mac1 and mac2 and mac3 and mac4 and mac5 and mac6) then
						mac = "FF:FF:FF:FF:FF:FF"
					else
						mac = mac1..":"..mac2..":"..mac3..":"..mac4..":"..mac5..":"..mac6
					end
					rv[#rv+1] = {
						expires  = (expire >= 0) and os.difftime(expire, os.time()),
						macaddr  = duid,
						macaddr  = mac:lower(),
						ipaddr   = ip,
						hostname = (name ~= "-") and name
					}
				end
			end
		end
		fd:close()
	end

	return rv
end

function dhcp_leases()
	return dhcp_leases_common(4)
end

function dhcp6_leases()
	return dhcp_leases_common(6)
end

function ipv6_neighbors()
	local ip = require "luci.ip"
	local webadmin = require "luci.tools.webadmin"
	local t = {}
	for _, v in ipairs(ip.neighbors({ family = 6 })) do
		if v.dest and not v.dest:is6linklocal() and v.mac then
			t[#t + 1] = {
				dest = tostring(v.dest),
				mac = tostring(v.mac),
				iface = webadmin.iface_get_network(v.dev) or '(' .. v.dev .. ')'
			}
		end
	end
	return t
end

function guess_wifi_hw(dev)
	local bands = ""
	local bands_table = {}
	local ifname = dev:name()
	local name, idx = ifname:match("^([a-z]+)(%d+)")
	idx = tonumber(idx)

	if has_iwinfo then
		local bl = dev.iwinfo.hwmodelist
		if bl and next(bl) then
			if bl.a then bands_table[#bands_table + 1] = "a" end
			if bl.b then bands_table[#bands_table + 1] = "b" end
			if bl.g then bands_table[#bands_table + 1] = "g" end
			if bl.n then bands_table[#bands_table + 1] = "n" end
			if bl.ac then bands_table[#bands_table + 1] = "ac" end
			bands = table.concat(bands_table, "/")
		end

		local hw = dev.iwinfo.hardware_name
		if hw then
			return "%s 802.11%s" %{ hw, bands }
		end
	end

	-- wl.o
	if name == "wl" then
		local name = i18n.translatef("Broadcom 802.11%s Wireless Controller", bands)
		local nm   = 0

		local fd = nixio.open("/proc/bus/pci/devices", "r")
		if fd then
			local ln
			for ln in fd:linesource() do
				if ln:match("wl$") then
					if nm == idx then
						local version = ln:match("^%S+%s+%S%S%S%S([0-9a-f]+)")
						name = i18n.translatef(
							"Broadcom BCM%04x 802.11 Wireless Controller",
							tonumber(version, 16)
						)

						break
					else
						nm = nm + 1
					end
				end
			end
			fd:close()
		end

		return name

	-- ralink
	elseif name == "ra" or name == "rai" then
		return i18n.translatef("Ralink/MediaTek 802.11%s Wireless Controller", bands)

	-- hermes
	elseif name == "eth" then
		return i18n.translate("Hermes 802.11b Wireless Controller")
		
	elseif name == "host" then
		return i18n.translate("Quantenna 802.11ac Wireless Controller")
		
	-- hostap
	elseif name == "wlan" and fs.stat("/proc/net/hostap/" .. ifname, "type") == "dir" then
		return i18n.translate("Prism2/2.5/3 802.11b Wireless Controller")

	-- dunno yet
	else
		return i18n.translatef("Generic 802.11%s Wireless Controller", bands)
	end
end

function wifi_networks()
	local rv = { }
	local ntm = require "luci.model.network".init()

	local dev
	for _, dev in ipairs(ntm:get_wifidevs()) do
		local rd = {
			up       = dev:is_up(),
			device   = dev:name(),
			--name     = dev:get_i18n(),
			name    = guess_wifi_hw(dev) .. " (" .. dev:name() .. ")",
			networks = { }
		}

		local net
		for _, net in ipairs(dev:get_wifinets()) do
			rd.networks[#rd.networks+1] = {
				name       = net:shortname(),
				link       = net:adminlink(),
				up         = net:is_up(),
				mode       = net:active_mode(),
				ssid       = net:active_ssid(),
				bssid      = net:active_bssid(),
				encryption = net:active_encryption(),
				frequency  = net:frequency(),
				channel    = net:channel(),
				signal     = net:signal(),
				quality    = net:signal_percent(),
				noise      = net:noise(),
				bitrate    = net:bitrate(),
				ifname     = net:ifname(),
				assoclist  = net:assoclist(),
				country    = net:country(),
				txpower    = net:txpower(),
				txpoweroff = net:txpower_offset(),
				disabled   = (dev:get("disabled") == "1" or
				             net:get("disabled") == "1")
			}
		end

		rv[#rv+1] = rd
	end

	return rv
end

function wifi_network(id)
	local ntm = require "luci.model.network".init()
	local net = ntm:get_wifinet(id)
	if net then
		local dev = net:get_device()
		if dev then
			return {
				id         = id,
				name       = net:shortname(),
				link       = net:adminlink(),
				up         = net:is_up(),
				mode       = net:active_mode(),
				ssid       = net:active_ssid(),
				bssid      = net:active_bssid(),
				encryption = net:active_encryption(),
				frequency  = net:frequency(),
				channel    = net:channel(),
				signal     = net:signal(),
				quality    = net:signal_percent(),
				noise      = net:noise(),
				bitrate    = net:bitrate(),
				ifname     = net:ifname(),
				assoclist  = net:assoclist(),
				country    = net:country(),
				txpower    = net:txpower(),
				txpoweroff = net:txpower_offset(),
				disabled   = (dev:get("disabled") == "1" or
				              net:get("disabled") == "1"),
				device     = {
					up     = dev:is_up(),
					device = dev:name(),
					--name   = dev:get_i18n()
					name    = guess_wifi_hw(dev) .. " (" .. dev:name() .. ")"
				}
			}
		end
	end
	return { }
end

function switch_status(devs)
	local dev
	local switches = { }
	for dev in devs:gmatch("[^%s,]+") do
		local ports = { }
		local swc = io.popen("swconfig dev %q show" % dev, "r")
		if swc then
			local l
			repeat
				l = swc:read("*l")
				if l then
					local port, up = l:match("port:(%d+) link:(%w+)")
					if port then
						local speed  = l:match(" speed:(%d+)")
						local duplex = l:match(" (%w+)-duplex")
						local txflow = l:match(" (txflow)")
						local rxflow = l:match(" (rxflow)")
						local auto   = l:match(" (auto)")

						ports[#ports+1] = {
							port   = tonumber(port) or 0,
							speed  = tonumber(speed) or 0,
							link   = (up == "up"),
							duplex = (duplex == "full"),
							rxflow = (not not rxflow),
							txflow = (not not txflow),
							auto   = (not not auto)
						}
					end
				end
			until not l
			swc:close()
		end
		switches[dev] = ports
	end
	return switches
end
