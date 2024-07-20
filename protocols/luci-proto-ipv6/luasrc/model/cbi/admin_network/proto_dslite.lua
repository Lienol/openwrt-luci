-- Copyright 2011 Jo-Philipp Wich <jow@openwrt.org>
-- Copyright 2013 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...

local peeraddr, ip6addr
local tunlink, mtu




peeraddr = section:taboption("general", Value, "peeraddr",
	translate("DS-Lite AFTR address"))

peeraddr.rmempty  = false
peeraddr.datatype = "or(hostname,ip6addr)"


ip6addr = section:taboption("general", Value, "ip6addr",
	translate("Local IPv6 address"),
	translate("Leave empty to use the current WAN address"))

ip6addr.datatype = "ip6addr"


tunlink = section:taboption("advanced", DynamicList, "tunlink", translate("Tunnel Link"))
tunlink.template = "cbi/network_netlist"
tunlink.nocreate = true


encaplimit = section:taboption("advanced", ListValue, "encaplimit", translate("Encapsulation limit"))
encaplimit.rmempty  = false
encaplimit.default  = "ignore"
encaplimit.datatype = 'or("ignore",range(0,255))'
encaplimit:value("ignore", translate("ignore"))
for i=1,256 do encaplimit:value(i) end


mtu = section:taboption("advanced", Value, "mtu", translate("Use MTU on tunnel interface"))
mtu.placeholder = "1280"
mtu.datatype    = "max(9200)"
