-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...

local server, username, password
local ipv6, mtu


server = section:taboption("general", Value, "server", translate("L2TP Server"))
server.datatype = "or(host(1), hostport(1))"


username = section:taboption("general", Value, "username", translate("PAP/CHAP username"))


password = section:taboption("general", Value, "password", translate("PAP/CHAP password"))
password.password = true


if luci.model.network:has_ipv6() then
	ipv6 = section:taboption("advanced", ListValue, "ipv6",
		translate("Obtain IPv6-Address"),
		translate("Enable IPv6 negotiation on the PPP link"))
	ipv6:value("auto", translate("Automatic"))
	ipv6:value("0", translate("Disabled"))
	ipv6:value("1", translate("Manual"))
	ipv6.default = "auto"
end

mtu = section:taboption("advanced", Value, "mtu", translate("Override MTU"))
mtu.placeholder = "1500"
mtu.datatype    = "max(9200)"
