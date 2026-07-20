-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2010-2012 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local sys = require "luci.sys"
local utl = require "luci.util"
local dsp = require "luci.dispatcher"
local nxo = require "nixio"

local ft = require "luci.tools.firewall"
local nw = require "luci.model.network"
local m, s, o, k, v

arg[1] = arg[1] or ""

m = Map("firewall", translate("Firewall - Traffic Rules"))

m.redirect = dsp.build_url("admin/network/firewall/rules")

nw.init(m.uci)

local rule_type = m.uci:get("firewall", arg[1])
if rule_type == "redirect" and m:get(arg[1], "target") ~= "SNAT" then
	rule_type = nil
end

if not rule_type then
	luci.http.redirect(m.redirect)
	return

--
-- SNAT
--
elseif rule_type == "redirect" then

	local name = m:get(arg[1], "name") or m:get(arg[1], "_name")
	if not name or #name == 0 then
		name = translate("(Unnamed SNAT)")
	else
		name = "SNAT %s" % name
	end

	m.title = "%s - %s" %{ translate("Firewall - Traffic Rules"), name }

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
	o.nocreate = true
	o.default = "wan"
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


	o = s:taboption("general", Value, "dest", translate("Destination zone"))
	o.nocreate = true
	o.default = "lan"
	o.template = "cbi/firewall_zonelist"


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


	o = s:taboption("general", Value, "src_dip", translate("SNAT IP address"),
		translate("Rewrite matched traffic to the given address."))
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


	o = s:taboption("general", Value, "src_dport", translate("SNAT port"),
		translate("Rewrite matched traffic to the given source port. May be \
			left empty to only rewrite the IP address."))
	o.datatype = "portrange"
	o.rmempty = true
	o.placeholder = translate('Do not rewrite')
	o:depends("proto", "tcp")
	o:depends("proto", "udp")
	o:depends("proto", "tcp udp")
	o:depends("proto", "tcpudp")


	o = s:taboption("advanced", Value, "extra", translate("Extra arguments"),
		translate("Passes additional arguments to iptables. Use with care!"))
--
-- Rule
--
else
	local name = m:get(arg[1], "name") or m:get(arg[1], "_name")
	if not name or #name == 0 then
		name = translate("(Unnamed Rule)")
	end

	m.title = "%s - %s" %{ translate("Firewall - Traffic Rules"), name }


	s = m:section(NamedSection, arg[1], "rule", "")
	s.anonymous = true
	s.addremove = false

	s:tab("general",  translate("General Settings"))
	s:tab("advanced", translate("Advanced Settings"))
	s:tab("timed", translate("Time Restrictions"))

	o = s:taboption("general", Flag, "enabled", translate("Enable"))
	o.default = o.enabled

	o = s:taboption("general", Value, "name", translate("Name"))
	o.rmempty = false

	o = s:taboption("advanced", ListValue, "direction", translate("Match device"))
	o:value("", translate("unspecified"))
	o:value("in", translate("Inbound device"))
	o:value("out", translate("Outbound device"))
	function o.cfgvalue(...)
		local v = Value.cfgvalue(...)
		if v == "in" or v == "ingress" then
			return "in"
		end
		if v == "out" or v == "egress" then
			return "out"
		end
		return nil
	end

	o = s:taboption("advanced", Value, "device", translate("Device name"), translate("Specifies whether to tie this traffic rule to a specific inbound or outbound network device."))
	m.uci:foreach("network", "device", function(e)
		o:value(e.name)
	end)
	for _, iface in ipairs(nw:get_interfaces()) do
		o:value(iface:name(), iface:get_i18n())
	end
	if #o.keylist > 0 then
		o.default = o.keylist[1]
	end
	o:depends("direction", "in")
	o:depends("direction", "out")

	o = s:taboption("advanced", ListValue, "family", translate("Restrict to address family"))
	o.rmempty = true
	o:value("", translate("IPv4 and IPv6"))
	o:value("ipv4", translate("IPv4 only"))
	o:value("ipv6", translate("IPv6 only"))


	o = s:taboption("general", Value, "proto", translate("Protocol"))
	o:value("all", translate("Any"))
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


	o = s:taboption("advanced", DynamicList, "icmp_type", translate("Match ICMP type"))
	o:value("", "any")
	o:value("echo-reply")
	o:value("destination-unreachable")
	o:value("network-unreachable")
	o:value("host-unreachable")
	o:value("protocol-unreachable")
	o:value("port-unreachable")
	o:value("fragmentation-needed")
	o:value("source-route-failed")
	o:value("network-unknown")
	o:value("host-unknown")
	o:value("network-prohibited")
	o:value("host-prohibited")
	o:value("TOS-network-unreachable")
	o:value("TOS-host-unreachable")
	o:value("communication-prohibited")
	o:value("host-precedence-violation")
	o:value("precedence-cutoff")
	o:value("source-quench")
	o:value("redirect")
	o:value("network-redirect")
	o:value("host-redirect")
	o:value("TOS-network-redirect")
	o:value("TOS-host-redirect")
	o:value("echo-request")
	o:value("router-advertisement")
	o:value("router-solicitation")
	o:value("time-exceeded")
	o:value("ttl-zero-during-transit")
	o:value("ttl-zero-during-reassembly")
	o:value("parameter-problem")
	o:value("ip-header-bad")
	o:value("required-option-missing")
	o:value("timestamp-request")
	o:value("timestamp-reply")
	o:value("address-mask-request")
	o:value("address-mask-reply")

	o:depends("proto", "icmp")


	o = s:taboption("general", Value, "src", translate("Source zone"))
	o.nocreate = true
	o.allowany = true
	o.default = "wan"
	o.template = "cbi/firewall_zonelist"


	o = s:taboption("advanced", Value, "ipset", translate("Use ipset"))


	o = s:taboption("advanced", Value, "src_mac", translate("Source MAC address"))
	o.datatype = "list(macaddr)"
	o.placeholder = translate("any")
	luci.sys.net.mac_hints(function(mac, name)
		o:value(mac, "%s (%s)" %{ mac, name })
	end)


	o = s:taboption("general", Value, "src_ip", translate("Source address"))
	o.datatype = "neg(ipmask)"
	o.placeholder = translate("any")
	luci.sys.net.ipv4_hints(function(ip, name)
		o:value(ip, "%s (%s)" %{ ip, name })
	end)


	o = s:taboption("general", Value, "src_port", translate("Source port"))
	o.datatype = "list(neg(portrange))"
	o.placeholder = translate("any")
	o:depends("proto", "tcp")
	o:depends("proto", "udp")
	o:depends("proto", "tcp udp")
	o:depends("proto", "tcpudp")


	o = s:taboption("general", Value, "dest", translate("Destination zone"))
	o.nocreate = true
	o.allowany = true
	o.allowlocal = true
	o.template = "cbi/firewall_zonelist"


	o = s:taboption("general", Value, "dest_ip", translate("Destination address"))
	o.datatype = "neg(ipmask)"
	o.placeholder = translate("any")
	luci.sys.net.ipv4_hints(function(ip, name)
		o:value(ip, "%s (%s)" %{ ip, name })
	end)


	o = s:taboption("general", Value, "dest_port", translate("Destination port"))
	o.datatype = "list(neg(portrange))"
	o.placeholder = translate("any")
	o:depends("proto", "tcp")
	o:depends("proto", "udp")
	o:depends("proto", "tcp udp")
	o:depends("proto", "tcpudp")


	o = s:taboption("general", ListValue, "target", translate("Action"))
	o.default = "ACCEPT"
	o:value("DROP", translate("drop"))
	o:value("ACCEPT", translate("accept"))
	o:value("REJECT", translate("reject"))
	o:value("NOTRACK", translate("don't track"))


	o = s:taboption("advanced", Flag, "log", translate("Enable logging"), translate("Log matched packets to syslog."))


	o = s:taboption("advanced", Value, "log_limit", translate("Limit log messages"))
	o.placeholder = "10/minute"
	o:depends("log", true)


	s:taboption("advanced", Value, "extra",
		translate("Extra arguments"),
		translate("Passes additional arguments to iptables. Use with care!"))
end

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