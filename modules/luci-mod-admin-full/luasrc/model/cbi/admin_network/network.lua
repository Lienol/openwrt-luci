-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2008 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local fs = require "nixio.fs"
local utl = require "luci.util"

m = Map("network", translate("Interfaces"))
m.pageaction = false
m:section(SimpleSection).template = "admin_network/iface_overview"

if fs.access("/etc/init.d/dsl_control") then
	dsl = m:section(TypedSection, "dsl", translate("DSL"))

	dsl.anonymous = true

	annex = dsl:option(ListValue, "annex", translate("Annex"))
	annex:value("a", translate("Annex A + L + M (all)"))
	annex:value("b", translate("Annex B (all)"))
	annex:value("j", translate("Annex J (all)"))
	annex:value("m", translate("Annex M (all)"))
	annex:value("bdmt", translate("Annex B G.992.1"))
	annex:value("b2", translate("Annex B G.992.3"))
	annex:value("b2p", translate("Annex B G.992.5"))
	annex:value("at1", translate("ANSI T1.413"))
	annex:value("admt", translate("Annex A G.992.1"))
	annex:value("alite", translate("Annex A G.992.2"))
	annex:value("a2", translate("Annex A G.992.3"))
	annex:value("a2p", translate("Annex A G.992.5"))
	annex:value("l", translate("Annex L G.992.3 POTS 1"))
	annex:value("m2", translate("Annex M G.992.3"))
	annex:value("m2p", translate("Annex M G.992.5"))

	tone = dsl:option(ListValue, "tone", translate("Tone"))
	tone:value("", translate("auto"))
	tone:value("a", translate("A43C + J43 + A43"))
	tone:value("av", translate("A43C + J43 + A43 + V43"))
	tone:value("b", translate("B43 + B43C"))
	tone:value("bv", translate("B43 + B43C + V43"))

	xfer_mode = dsl:option(ListValue, "xfer_mode", translate("Encapsulation mode"))
	xfer_mode:value("", translate("auto"))
	xfer_mode:value("atm", translate("ATM (Asynchronous Transfer Mode)"))
	xfer_mode:value("ptm", translate("PTM/EFM (Packet Transfer Mode)"))

	line_mode = dsl:option(ListValue, "line_mode", translate("DSL line mode"))
	line_mode:value("", translate("auto"))
	line_mode:value("adsl", translate("ADSL"))
	line_mode:value("vdsl", translate("VDSL"))

	firmware = dsl:option(Value, "firmware", translate("Firmware File"))

	m.pageaction = true
end

-- Show ATM bridge section if we have the capabilities
if fs.access("/usr/sbin/br2684ctl") then
	atm = m:section(TypedSection, "atm-bridge", translate("ATM Bridges"),
		translate("ATM bridges expose encapsulated ethernet in AAL5 " ..
			"connections as virtual Linux network interfaces which can " ..
			"be used in conjunction with DHCP or PPP to dial into the " ..
			"provider network."))

	atm.addremove = true
	atm.anonymous = true

	atm.create = function(self, section)
		local sid = TypedSection.create(self, section)
		local max_unit = -1

		m.uci:foreach("network", "atm-bridge",
			function(s)
				local u = tonumber(s.unit)
				if u ~= nil and u > max_unit then
					max_unit = u
				end
			end)

		m.uci:set("network", sid, "unit", max_unit + 1)
		m.uci:set("network", sid, "atmdev", 0)
		m.uci:set("network", sid, "encaps", "llc")
		m.uci:set("network", sid, "payload", "bridged")
		m.uci:set("network", sid, "vci", 35)
		m.uci:set("network", sid, "vpi", 8)

		return sid
	end

	atm:tab("general", translate("General Setup"))
	atm:tab("advanced", translate("Advanced Settings"))

	vci    = atm:taboption("general", Value, "vci", translate("ATM Virtual Channel Identifier (VCI)"))
	vpi    = atm:taboption("general", Value, "vpi", translate("ATM Virtual Path Identifier (VPI)"))
	encaps = atm:taboption("general", ListValue, "encaps", translate("Encapsulation mode"))
	encaps:value("llc", translate("LLC"))
	encaps:value("vc", translate("VC-Mux"))

	atmdev  = atm:taboption("advanced", Value, "atmdev", translate("ATM device number"))
	unit    = atm:taboption("advanced", Value, "unit", translate("Bridge unit number"))
	payload = atm:taboption("advanced", ListValue, "payload", translate("Forwarding mode"))
	payload:value("bridged", translate("bridged"))
	payload:value("routed", translate("routed"))
	m.pageaction = true
end

local packet_steering = fs.access("/usr/libexec/network/packet-steering.sh") or fs.access("/usr/libexec/network/packet-steering.uc")
local network = require "luci.model.network"
if network:has_ipv6() or packet_steering then
	local s = m:section(NamedSection, "globals", "globals", translate("Global network options"))

	if network:has_ipv6() then
		local o = s:option(Value, "ula_prefix", translate("IPv6 ULA-Prefix"),
			translate('ULA for IPv6 is analogous to IPv4 private network addressing.') ..
			translate('This prefix is randomly generated at first install.'))
		o.datatype = "ip6addr"
		o.rmempty = true
		m.pageaction = true
	end

	if packet_steering then
		local o = s:option(ListValue, "packet_steering", translate("Packet Steering"), translate("Enable packet steering across CPUs. May help or hinder network speed."))
		o:value('', translate('Disabled'))
		o:value('1', translate('Enabled'))
		o:value('2', translate('Enabled (all CPUs)'))

		local o = s:option(ListValue, "steering_flows", translate('Steering flows (<abbr title="Receive Packet Steering">RPS</abbr>)'),
			translate('Directs packet flows to specific CPUs where the local socket owner listens (the local service).') .. 
			translate('Note: this setting is for local services on the device only (not for forwarding).'))
		o:value('', translate('Standard: none'))
		o:value('128', translate('Suggested: 128'))
		o:value('256', translate('256'))
		o:depends("packet_steering", "1")
		o:depends("packet_steering", "2")
		o.datatype = "uinteger"
	end
end

if network.new_netifd then
	s = m:section(TypedSection, "device", translate("Devices"))
	s.addremove = true
	s.anonymous = true
	s.template = "cbi/tblsection"
	local extedit = luci.dispatcher.build_url("admin/network/device/%s")
	function s.create(e, t)
		local sid = TypedSection.create(e, t)
		luci.http.redirect(extedit:format(sid))
	end
	s.extedit = extedit .. "/edit"
	function s.remove(e, t)
		local name = m:get(t, "name")
		if name then
			m.uci:foreach("network", "bridge-vlan", function(s)
				if s.device and s.device == name then
					m.uci:delete("network", s[".name"])
				end
			end)
		end
		s.map.proceed = true
		s.map:del(t)
	end

	o = s:option(DummyValue, "name", translate("Device"))

	o = s:option(DummyValue, "type", translate("Type"))
	o.cfgvalue = function(t, n)
		local v = Value.cfgvalue(t, n)
		if v == "" then
			return translate("Device not present")
		elseif v == "8021q" then
			return translate("VLAN (802.1q)")
		elseif v == "8021ad" then
			return translate("VLAN (802.1ad)")
		elseif v == "bridge" then
			return translate("Bridge device")
		elseif v == "tunnel" then
			return translate("Tunnel device")
		elseif v == "macvlan" then
			return translate("MAC VLAN")
		elseif v == "veth" then
			return translate("Virtual Ethernet")
		else
			return translate("Network device")
		end
	end

	o = s:option(DummyValue, "macaddr", translate("MAC Address"))
	o.cfgvalue = function(t, n)
		local v = Value.cfgvalue(t, n)
		if not v then
			local e = m:get(n)
			if e.name then
				local eth = e.name
				if e.ifname then
					eth = e.ifname
				end
				v = utl.exec('cat /sys/class/net/%s/address 2>/dev/null' % eth)
			end
		end
		return v
	end
end


return m
