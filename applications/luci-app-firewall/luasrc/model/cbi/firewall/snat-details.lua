local sys = require "luci.sys"
local utl = require "luci.util"
local dsp = require "luci.dispatcher"
local nxo = require "nixio"

local ft = require "luci.tools.firewall"
local nw = require "luci.model.network"
local m, s, o, k, v

arg[1] = arg[1] or ""

m = Map("firewall", translate("Firewall - NAT Rules"))
m.redirect = dsp.build_url("admin/network/firewall/snats")
nw.init(m.uci)

local name = m:get(arg[1], "name") or m:get(arg[1], "_name")
if not name or #name == 0 then
	name = translate("(Unnamed Entry)")
end

m.title = "%s - %s" %{ translate("Firewall - NAT Rules"), name }

local wan_zone = nil

m.uci:foreach("firewall", "zone",
	function(s)
		local n = s.network or s.name
		if n then
			local i
			for i in utl.imatch(n) do
				if i == "wan" then
					wan_zone = s.name
					return false
				end
			end
		end
	end)

s = m:section(NamedSection, arg[1], "redirect", "")
s.anonymous = true
s.addremove = false

s:tab("general",  translate("General Settings"))
s:tab("advanced", translate("Advanced Settings"))
s:tab("timed", translate("Time Restrictions"))

o = s:taboption("general", Flag, "enabled", translate("Enable"))
o.default = o.enabled

o = s:taboption("general", Value, "name", translate("Name"))
o.rmempty = false

o = s:taboption("general", Value, "proto", translate("Protocol"))
o:value("all", "All protocols")
o:value("tcp udp", "TCP+UDP")
o:value("tcp", "TCP")
o:value("udp", "UDP")
o:value("icmp", "ICMP")
function o.cfgvalue(...)
	local v = Value.cfgvalue(...)
	if not v or v == "tcpudp" then
		return "tcp udp"
	end
	return v
end


o = s:taboption("general", Value, "src", translate("Source zone"))
o.allowany = true
o.nocreate = true
o.default = "lan"
o.template = "cbi/firewall_zonelist"


o = s:taboption("general", Value, "src_ip", translate("Source IP address"))
o.rmempty = true
o.datatype = "neg(ipmask4)"
o.placeholder = translate("any")
luci.sys.net.ipv4_hints(function(ip, name)
	o:value(ip, "%s (%s)" %{ ip, name })
end)


o = s:taboption("general", Value, "src_port",
	translate("Source port"),
	translate("Match incoming traffic originating from the given source \
		port or port range on the client host."))
o.rmempty = true
o.datatype = "neg(portrange)"
o.placeholder = translate("any")
o:depends("proto", "tcp")
o:depends("proto", "udp")
o:depends("proto", "tcp udp")
o:depends("proto", "tcpudp")


o = s:taboption("general", Value, "dest_ip", translate("Destination IP address"))
o.datatype = "neg(ipmask4)"
luci.sys.net.ipv4_hints(function(ip, name)
	o:value(ip, "%s (%s)" %{ ip, name })
end)


o = s:taboption("general", Value, "dest_port", translate("Destination port"),
	translate("Match forwarded traffic to the given destination port or \
		port range."))
o.rmempty = true
o.placeholder = translate("any")
o.datatype = "neg(portrange)"
o:depends("proto", "tcp")
o:depends("proto", "udp")
o:depends("proto", "tcp udp")
o:depends("proto", "tcpudp")


o = s:taboption("general", ListValue, "target", translate("Action"))
o.default = "SNAT"
o:value("SNAT", translate("SNAT - Rewrite to specific source IP or port"))
o:value("MASQUERADE", translate("MASQUERADE - Automatically rewrite to outbound interface IP"))
o:value("ACCEPT", translate("ACCEPT - Disable address rewriting"))


o = s:taboption("general", Value, "snat_ip", translate("Rewrite IP address"),
	translate("Rewrite matched traffic to the specified source IP address."))
o:depends("target", "SNAT")
o.rmempty = false
o.datatype = "ip4addr"
for k, v in ipairs(nw:get_interfaces()) do
	local a
	for k, a in ipairs(v:ipaddrs()) do
		o:value(a:host():string(), '%s (%s)' %{
			a:host():string(), v:shortname()
		})
	end
end


o = s:taboption("general", Value, "snat_port", translate("Rewrite port"),
	translate("Rewrite matched traffic to the specified source port or port range."))
o.datatype = "portrange"
o.rmempty = true
o.placeholder = translate('Do not rewrite')
o:depends({proto = "tcp", target = "SNAT"})
o:depends({proto = "udp", target = "SNAT"})
o:depends({proto = "tcp udp", target = "SNAT"})
o:depends({proto = "tcpudp", target = "SNAT"})


o = s:taboption("advanced", Value, "ipset", translate("Use ipset"))


o = s:taboption("advanced", Value, "device", translate("Outbound device"), translate("Matches forwarded traffic using the specified outbound network device."))
m.uci:foreach("network", "device", function(e)
	o:value(e.name)
end)
for _, iface in ipairs(nw:get_interfaces()) do
	o:value(iface:name(), iface:get_i18n())
end

o = s:taboption("advanced", Flag, "log", translate("Enable logging"), translate("Log matched packets to syslog."))


o = s:taboption("advanced", Value, "extra", translate("Extra arguments"),
	translate("Passes additional arguments to iptables. Use with care!"))


o = s:taboption("timed", MultiValue, "weekdays", translate("Week Days"))
o.oneline = true
o.widget = "checkbox"
o:value("Sun", translate("Sunday"))
o:value("Mon", translate("Monday"))
o:value("Tue", translate("Tuesday"))
o:value("Wed", translate("Wednesday"))
o:value("Thu", translate("Thursday"))
o:value("Fri", translate("Friday"))
o:value("Sat", translate("Saturday"))

o = s:taboption("timed", MultiValue, "monthdays", translate("Month Days"))
o.oneline = true
o.widget = "checkbox"
for i = 1,31 do
	o:value(translate(i))
end

o = s:taboption("timed", Value, "start_time", translate("Start Time (hh:mm:ss)"))
o.datatype = "timehhmmss"
o = s:taboption("timed", Value, "stop_time", translate("Stop Time (hh:mm:ss)"))
o.datatype = "timehhmmss"
o = s:taboption("timed", Value, "start_date", translate("Start Date (yyyy-mm-dd)"))
o.datatype = "dateyyyymmdd"
o = s:taboption("timed", Value, "stop_date", translate("Stop Date (yyyy-mm-dd)"))
o.datatype = "dateyyyymmdd"

o = s:taboption("timed", Flag, "utc_time", translate("Time in UTC"))
o.default = o.disabled

return m