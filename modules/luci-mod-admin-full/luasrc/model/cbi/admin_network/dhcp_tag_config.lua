m = Map("dhcp")

s = m:section(NamedSection, arg[1], translate("Tag"), translate("Tag"))
s.addremove = false
s.dynamic = false

o = s:option(DynamicList, "dhcp_option", translate("DHCP-Options"),
	translate("Define additional DHCP options, for example \"<code>6,192.168.2.1," ..
		"192.168.2.2</code>\" which advertises different DNS servers to clients."))

o = s:option(Flag, "force", translate("Force") .. " " .. translate("DHCP-Options"))
o.default = 0
o.rmempty  = false

return m
