m = Map("natmap", translate("NATMap"))
m.redirect = luci.dispatcher.build_url("admin", "services", "natmap")

s = m:section(NamedSection, arg[1], "natmap", "")
s.addremove = false
s.dynamic = false

o = s:option(Flag, "enable", translate("Enable"))
o.default = "1"
o.rmempty = false

o = s:option(ListValue, "udp_mode", translate("Protocol"))
o.default = "1"
o:value("0", "TCP")
o:value("1", "UDP")

o = s:option(ListValue, "family", translate("Restrict to address family"))
o:value("", translate("IPv4 and IPv6"))
o:value("ipv4", translate("IPv4 only"))
o:value("ipv6", translate("IPv6 only"))

o = s:option(Value, "interface", translate("Interface"))
o.template = "cbi/network_netlist"
o.nocreate = true

o = s:option(Value, "interval", translate("Keep-alive interval"))
o.datatype = "and(uinteger, min(1))"

o = s:option(Value, "stun_cycle", translate("STUN check cycle"), translate("For UDP mode"))
o.datatype = "uinteger"
o:depends("udp_mode", "1")

o = s:option(Value, "stun_server", translate("STUN server"))
o:value("turn.cloudflare.com")
o:value("stun.cloudflare.com")
o.datatype = "string"
o.rmempty = false

o = s:option(Value, "http_server", translate("HTTP server"), translate("For TCP mode"))
o.datatype = "string"
o.rmempty = false

o = s:option(Value, "fwmark", translate("Fwmark"), translate("Mark fwmark for STUN/HTTP outbound traffic"))
o.datatype = "string"

o = s:option(Value, "port", translate("Bind port"))
o.datatype = "or(port, portrange)"
o.rmempty = false

o = s:option(Flag, "port_random", translate("Randomly allocation ports"), translate("Allocation bind ports randomly instead of sequentially."))

o = s:option(Flag, "_forward_mode", translate("Forward mode"))
function o.cfgvalue(self, section)
	local val = self.map:get(section, "forward_target")
	return (val and val ~= "") and "1" or "0"
end
function o.write(self, section, value)
end

o = s:option(Value, "forward_target", translate("Forward target"))
o.datatype = "host"
o:depends("_forward_mode", "1")

o = s:option(Value, "forward_port", translate("Forward target port"))
o.datatype = "port"
o:depends("_forward_mode", "1")

o = s:option(Value, "forward_timeout", translate("Forward timeout"))
o.datatype = "and(uinteger, min(1))"
o:depends("_forward_mode", "1")

o = s:option(Value, "forward_congestion", translate("Congestion control"), translate("For TCP mode"))
o.datatype = "string"
o:depends({ _forward_mode = "1", udp_mode = "0" })

o = s:option(Value, "notify_script", translate("Notify script"))
o.datatype = "file"

return m