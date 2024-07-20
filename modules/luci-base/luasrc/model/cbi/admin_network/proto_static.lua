-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...
local ifc = net:get_interface()

local ipaddr, netmask, gateway, broadcast, ip6addr, ip6gw


ipaddr = section:taboption("general", Value, "ipaddr", translate("IPv4 address"))
ipaddr.datatype = "ip4addr"


netmask = section:taboption("general", Value, "netmask",
	translate("IPv4 netmask"))

netmask.datatype = "ip4addr"
netmask:value("255.255.255.0")
netmask:value("255.255.0.0")
netmask:value("255.0.0.0")


gateway = section:taboption("general", Value, "gateway", translate("IPv4 gateway"))
gateway.datatype = "ip4addr"


broadcast = section:taboption("general", Value, "broadcast", translate("IPv4 broadcast Address"))
broadcast.datatype = "ip4addr"

if luci.model.network:has_ipv6() then
	ip6addr = section:taboption("general", Value, "ip6addr", translate("IPv6 address"))
	ip6addr.datatype = "ip6addr"
	ip6addr:depends("ip6assign", "")


	ip6gw = section:taboption("general", Value, "ip6gw", translate("IPv6 gateway"))
	ip6gw.datatype = "ip6addr"
	ip6gw:depends("ip6assign", "")


	local ip6prefix = s:taboption("general", Value, "ip6prefix", translate("IPv6 routed prefix"),
		translate("Public prefix routed to this device for distribution to clients."))
	ip6prefix.datatype = "ip6addr"
	ip6prefix:depends("ip6assign", "")

end
