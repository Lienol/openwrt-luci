-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2008-2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

local fs = require "nixio.fs"
local ut = require "luci.util"
local pt = require "luci.tools.proto"
local nw = require "luci.model.network"
local fw = require "luci.model.firewall"

arg[1] = arg[1] or ""

local has_dnsmasq  = fs.access("/etc/config/dhcp")
local has_firewall = fs.access("/etc/config/firewall")

m = Map("network", translate("Interfaces") .. " - " .. arg[1]:upper(), translate("On this page you can configure the network interfaces. You can bridge several interfaces by ticking the \"bridge interfaces\" field and enter the names of several network interfaces separated by spaces. You can also use <abbr title=\"Virtual Local Area Network\">VLAN</abbr> notation <samp>INTERFACE.VLANNR</samp> (<abbr title=\"for example\">e.g.</abbr>: <samp>eth0.1</samp>)."))
m.redirect = luci.dispatcher.build_url("admin", "network", "network")
m:chain("wireless")

if has_firewall then
	m:chain("firewall")
end

nw.init(m.uci)
fw.init(m.uci)


local net = nw:get_network(arg[1])

local function backup_ifnames(is_bridge)
	if not net:is_floating() and not m:get(net:name(), "_orig_ifname") then
		local ifcs = net:get_interfaces() or { net:get_interface() }
		if ifcs then
			local _, ifn
			local ifns = { }
			for _, ifn in ipairs(ifcs) do
				ifns[#ifns+1] = ifn:name()
			end
			if #ifns > 0 then
				m:set(net:name(), "_orig_ifname", table.concat(ifns, " "))
				m:set(net:name(), "_orig_bridge", tostring(net:is_bridge()))
			end
		end
	end
end


-- redirect to overview page if network does not exist anymore (e.g. after a revert)
if not net then
	luci.http.redirect(luci.dispatcher.build_url("admin/network/network"))
	return
end

-- protocol switch was requested, rebuild interface config and reload page
if m:formvalue("cbid.network.%s._switch" % net:name()) then
	-- get new protocol
	local ptype = m:formvalue("cbid.network.%s.proto" % net:name()) or "-"
	local proto = nw:get_protocol(ptype, net:name())
	if proto then
		-- backup default
		backup_ifnames()

		-- if current proto is not floating and target proto is not floating,
		-- then attempt to retain the ifnames
		--error(net:proto() .. " > " .. proto:proto())
		if not net:is_floating() and not proto:is_floating() then
			-- if old proto is a bridge and new proto not, then clip the
			-- interface list to the first ifname only
			if net:is_bridge() and proto:is_virtual() then
				local _, ifn
				local first = true
				for _, ifn in ipairs(net:get_interfaces() or { net:get_interface() }) do
					if first then
						first = false
					else
						net:del_interface(ifn)
					end
				end
				m:del(net:name(), "type")
			end

		-- if the current proto is floating, the target proto not floating,
		-- then attempt to restore ifnames from backup
		elseif net:is_floating() and not proto:is_floating() then
			-- if we have backup data, then re-add all orphaned interfaces
			-- from it and restore the bridge choice
			local br = (m:get(net:name(), "_orig_bridge") == "true")
			local ifn
			local ifns = { }
			for ifn in ut.imatch(m:get(net:name(), "_orig_ifname")) do
				ifn = nw:get_interface(ifn)
				if ifn and not ifn:get_network() then
					proto:add_interface(ifn)
					if not br then
						break
					end
				end
			end
			if br then
				m:set(net:name(), "type", "bridge")
			end

		-- in all other cases clear the ifnames
		else
			local _, ifc
			for _, ifc in ipairs(net:get_interfaces() or { net:get_interface() }) do
				net:del_interface(ifc)
			end
			m:del(net:name(), "type")
		end

		-- clear options
		local k, v
		for k, v in pairs(m:get(net:name())) do
			if k:sub(1,1) ~= "." and
			   k ~= "type" and
			   k ~= "ifname" and
			   k ~= "_orig_ifname" and
			   k ~= "_orig_bridge" and
			   (nw.new_netifd and k ~= "device")
			then
				m:del(net:name(), k)
			end
		end

		-- set proto
		m:set(net:name(), "proto", proto:proto())
		m.uci:save("network")
		m.uci:save("wireless")

		-- reload page
		luci.http.redirect(luci.dispatcher.build_url("admin/network/network", arg[1]))
		return
	end
end

-- dhcp setup was requested, create section and reload page
if m:formvalue("cbid.dhcp._enable._enable") then
	m.uci:section("dhcp", "dhcp", arg[1], {
		interface = arg[1],
		start     = "100",
		limit     = "150",
		leasetime = "12h"
	})

	m.uci:save("dhcp")
	luci.http.redirect(luci.dispatcher.build_url("admin/network/network", arg[1]))
	return
end
if m:formvalue("cbid.dhcp." .. arg[1] .. "._delete") then
	m.uci:delete("dhcp", arg[1])
	m.uci:save("dhcp")
	luci.http.redirect(luci.dispatcher.build_url("admin/network/network", arg[1]))
	return
end

local ifc = net:get_interface()

s = m:section(NamedSection, arg[1], "interface", translate("Common Configuration"))
s.addremove = false

s:tab("general",  translate("General Setup"))
s:tab("advanced", translate("Advanced Settings"))
s:tab("physical", translate("Physical Settings"))

if has_firewall then
	s:tab("firewall", translate("Firewall Settings"))
end


st = s:taboption("general", DummyValue, "__status", translate("Status"))

local function set_status()
	-- if current network is empty, print a warning
	if not net:is_floating() and net:is_empty() then
		st.template = "cbi/dvalue"
		st.network  = nil
		st.value    = translate("There is no device assigned yet, please attach a network device in the \"Physical Settings\" tab")
	else
		st.template = "admin_network/iface_status"
		st.network  = arg[1]
		st.value    = nil
	end
end

m.on_init = set_status
m.on_after_save = set_status


p = s:taboption("general", ListValue, "proto", translate("Protocol"))
p.default = net:proto()


if not net:is_installed() then
	p_install = s:taboption("general", Button, "_install")
	p_install.title      = translate("Protocol support is not installed")
	p_install.inputtitle = translate("Install package %q" % net:opkg_package())
	p_install.inputstyle = "apply"
	p_install:depends("proto", net:proto())

	function p_install.write()
		return luci.http.redirect(
			luci.dispatcher.build_url("admin/system/packages") ..
			"?submit=1&install=%s" % net:opkg_package()
		)
	end
end


p_switch = s:taboption("general", Button, "_switch")
p_switch.title      = translate("Really switch protocol?")
p_switch.inputtitle = translate("Switch protocol")
p_switch.inputstyle = "apply"

local _, pr
for _, pr in ipairs(nw:get_protocols()) do
	p:value(pr:proto(), pr:get_i18n())
	if pr:proto() ~= net:proto() then
		p_switch:depends("proto", pr:proto())
	end
end

if nw.new_netifd then
	device = s:taboption("general", Value, "device", "<a style='color:red'>" .. translate("Device") .. "</a>")
	m.uci:foreach("network", "device", function(e)
		device:value(e.name)
	end)
	for _, iface in ipairs(nw:get_interfaces()) do
		device:value(iface:name(), iface:get_i18n())
	end
	device:depends("proto", "static")
	device:depends("proto", "dhcp")
	device:depends("proto", "none")
	device:depends("proto", "dhcpv6")
	device:depends("proto", "pppoe")
end


auto = s:taboption("advanced", Flag, "auto", translate("Bring up on boot"))
auto.default = (net:proto() == "none") and auto.disabled or auto.enabled

delegate = s:taboption("advanced", Flag, "delegate", translate("Use builtin IPv6-management"))
delegate.default = delegate.enabled

force_link = s:taboption("advanced", Flag, "force_link",
	translate("Force link"),
	translate("Set interface properties regardless of the link carrier (If set, carrier sense events do not invoke hotplug handlers)."))

force_link.default = (net:proto() == "static") and force_link.enabled or force_link.disabled

if not nw.new_netifd then
if not net:is_virtual() then
	br = s:taboption("physical", Flag, "type", translate("Bridge interfaces"), translate("creates a bridge over specified interface(s)"))
	br.enabled = "bridge"
	br.rmempty = true

	if nw.new_netifd then
		br.cfgvalue = function(self, section)
			local type = ""
			m.uci:foreach("network", "device", function(e)
				if e.name == m:get(section, "device") then
					type = e.type
				end
			end)
			return type
		end
		br.write = function(self, section, value)
			local flag = false
			m.uci:foreach("network", "device", function(e)
				if e.name == m:get(section, "device") then
					flag = true
					m.uci:set("network", e.name, "type", value)
				end
			end)
			if flag == false then
				if value == "bridge" then
					local id = m.uci:add("network", "device")
					m.uci:set("network", id, "name", "br-" .. section)
					m.uci:set("network", id, "type", "bridge")
					m.uci:set("network", section, "device", "br-" .. section)
				end
			end
			return
		end
	end
	br:depends("proto", "static")
	br:depends("proto", "dhcp")
	br:depends("proto", "none")

	stp = s:taboption("physical", Flag, "stp", translate("Enable <abbr title=\"Spanning Tree Protocol\">STP</abbr>"),
		translate("Enables the Spanning Tree Protocol on this bridge"))
	stp:depends("type", "bridge")
	stp.rmempty = true
	
	igmp = s:taboption("physical", Flag, "igmp_snooping", translate("Enable <abbr title=\"Internet Group Management Protocol\">IGMP</abbr> snooping"),
	translate("Enables IGMP snooping on this bridge"))
	igmp:depends("type", "bridge")
	igmp.rmempty = true
end


if not net:is_floating() then
	ifname_single = s:taboption("physical", Value, "ifname_single", translate("Interface"))
	ifname_single.template = "cbi/network_ifacelist"
	ifname_single.widget = "radio"
	ifname_single.nobridges = true
	ifname_single.rmempty = false
	ifname_single.network = arg[1]
	ifname_single:depends("type", "")

	function ifname_single.cfgvalue(self, s)
		-- let the template figure out the related ifaces through the network model
		return nil
	end

	function ifname_single.write(self, s, val)
		local i
		local new_ifs = { }
		local old_ifs = { }

		for _, i in ipairs(net:get_interfaces() or { net:get_interface() }) do
			old_ifs[#old_ifs+1] = i:name()
		end

		for i in ut.imatch(val) do
			new_ifs[#new_ifs+1] = i

			-- if this is not a bridge, only assign first interface
			if self.option == "ifname_single" then
				break
			end
		end

		table.sort(old_ifs)
		table.sort(new_ifs)

		for i = 1, math.max(#old_ifs, #new_ifs) do
			if old_ifs[i] ~= new_ifs[i] then
				backup_ifnames()
				for i = 1, #old_ifs do
					net:del_interface(old_ifs[i])
				end
				for i = 1, #new_ifs do
					net:add_interface(new_ifs[i])
				end
				break
			end
		end
	end
end


if not net:is_virtual() then
	ifname_multi = s:taboption("physical", Value, "ifname_multi", translate("Interface"))
	ifname_multi.template = "cbi/network_ifacelist"
	ifname_multi.nobridges = true
	ifname_multi.rmempty = false
	ifname_multi.network = arg[1]
	ifname_multi.widget = "checkbox"
	ifname_multi:depends("type", "bridge")
	ifname_multi.cfgvalue = ifname_single.cfgvalue
	ifname_multi.write = ifname_single.write
end
end


if has_firewall then
	fwzone = s:taboption("firewall", Value, "_fwzone",
		translate("Create / Assign firewall-zone"),
		translate("Choose the firewall zone you want to assign to this interface. Select <em>unspecified</em> to remove the interface from the associated zone or fill out the <em>create</em> field to define a new zone and attach the interface to it."))

	fwzone.template = "cbi/firewall_zonelist"
	fwzone.network = arg[1]
	fwzone.rmempty = false

	function fwzone.cfgvalue(self, section)
		self.iface = section
		local z = fw:get_zone_by_network(section)
		return z and z:name()
	end

	function fwzone.write(self, section, value)
		local zone = fw:get_zone(value)

		if not zone and value == '-' then
			value = m:formvalue(self:cbid(section) .. ".newzone")
			if value and #value > 0 then
				zone = fw:add_zone(value)
			else
				fw:del_network(section)
			end
		end

		if zone then
			fw:del_network(section)
			zone:add_network(section)
		end
	end
end


function p.write() end
function p.remove() end
function p.validate(self, value, section)
	if value == net:proto() then
		if not net:is_floating() and net:is_empty() then
			local ifn
			if not nw.new_netifd then
			ifn = ((br and (br:formvalue(section) == "bridge"))
				and ifname_multi:formvalue(section)
			     or ifname_single:formvalue(section))
			else
				ifn = device:formvalue(section)
			end

			for ifn in ut.imatch(ifn) do
				return value
			end
			return nil, translate("The selected protocol needs a device assigned")
		end
	end
	return value
end


local form, ferr = loadfile(
	ut.libpath() .. "/model/cbi/admin_network/proto_%s.lua" % net:proto()
)

if not form then
	s:taboption("general", DummyValue, "_error",
		translate("Missing protocol extension for proto %q" % net:proto())
	).value = ferr
else
	setfenv(form, getfenv(1))(m, s, net)
end


local _, field
for _, field in ipairs(s.children) do
	if field ~= st and field ~= p and field ~= p_install and field ~= p_switch and (nw.new_netifd and field ~= device) then
		if next(field.deps) then
			local _, dep
			for _, dep in ipairs(field.deps) do
				dep.proto = net:proto()
			end
		else
			field:depends("proto", net:proto())
		end
	end
end


--
-- Display DNS settings if dnsmasq is available
--

if has_dnsmasq and (net:proto() == "static" or net:proto() == "dhcpv6" or net:proto() == "none") then
	m2 = Map("dhcp", "", "")

	local has_section = false

	m2.uci:foreach("dhcp", "dhcp", function(s)
		if s.interface == arg[1] then
			has_section = true
			return false
		end
	end)

	if not has_section and has_dnsmasq then

		s = m2:section(TypedSection, "dhcp", translate("DHCP Server"))
		s.anonymous   = true
		s.cfgsections = function() return { "_enable" } end

		x = s:option(Button, "_enable")
		x.title      = translate("No DHCP Server configured for this interface")
		x.inputtitle = translate("Setup DHCP Server")
		x.inputstyle = "apply"

	elseif has_section then

		s = m2:section(TypedSection, "dhcp", translate("DHCP Server"))
		s.addremove = false
		s.anonymous = true
		s:tab("general",  translate("General Setup"))
		s:tab("advanced", translate("Advanced Settings"))
		s:tab("ipv6", translate("IPv6 Settings"))
		s:tab("ipv6-ra", translate("IPv6 RA Settings"))

		function s.filter(self, section)
			return m2.uci:get("dhcp", section, "interface") == arg[1]
		end

		local ignore = s:taboption("general", Flag, "ignore",
			translate("Ignore interface"),
			translate("Disable <abbr title=\"Dynamic Host Configuration Protocol\">DHCP</abbr> for " ..
				"this interface."))
		if net:proto() ~= "static" then
			ignore.default = "1"
			ignore.rmempty = false
		end

		local start = s:taboption("general", Value, "start", translate("Start"),
			translate("Lowest leased address as offset from the network address."))
		start.optional = true
		start.datatype = "or(uinteger,ip4addr)"
		start.default = "100"

		local limit = s:taboption("general", Value, "limit", translate("Limit"),
			translate("Maximum number of leased addresses."))
		limit.optional = true
		limit.datatype = "uinteger"
		limit.default = "150"

		local ltime = s:taboption("general", Value, "leasetime", translate("Lease time"),
			translate("Expiry time of leased addresses, minimum is 2 minutes (<code>2m</code>)."))
		ltime.rmempty = true
		ltime.default = "12h"

		x = s:taboption("general", Button, "_delete")
		x.title      = translate("Delete this DHCP Server")
		x.inputtitle = translate("Delete DHCP Server configured for this interface")
		x.inputstyle = "remove"

		if net:proto() == "static" then

		local dd = s:taboption("advanced", Flag, "dynamicdhcp",
			translate("Dynamic <abbr title=\"Dynamic Host Configuration Protocol\">DHCP</abbr>"),
			translate("Dynamically allocate DHCP addresses for clients. If disabled, only " ..
				"clients having static leases will be served."))
		dd.default = dd.enabled

		s:taboption("advanced", Flag, "force", translate("Force"),
			translate("Force DHCP on this network even if another server is detected."))

		-- XXX: is this actually useful?
		--s:taboption("advanced", Value, "name", translate("Name"),
		--	translate("Define a name for this network."))

		mask = s:taboption("advanced", Value, "netmask",
			translate("<abbr title=\"Internet Protocol Version 4\">IPv4</abbr>-Netmask"),
			translate("Override the netmask sent to clients. Normally it is calculated " ..
				"from the subnet that is served."))

		mask.optional = true
		mask.datatype = "ip4addr"

		s:taboption("advanced", DynamicList, "dhcp_option", translate("DHCP-Options"),
			translate("Define additional DHCP options, for example \"<code>6,192.168.2.1," ..
				"192.168.2.2</code>\" which advertises different DNS servers to clients."))
--[[
		for i, n in ipairs(s.children) do
			if n ~= ignore then
				n:depends("ignore", "")
			end
		end
]]--
		end

		local has_other_master = nil
		m2.uci:foreach("dhcp", "dhcp", function(s)
			if s.interface ~= arg[1] and s.master == "1" then
				has_other_master = s
				return
			end
		end)

		o = s:taboption("ipv6", Flag, "master", translate("Designated master"))
		o.description = translate('Set this interface as master for RA and DHCPv6 relaying as well as NDP proxying.')
		if has_other_master then
			o.readonly = true
			o.description = translatef('Interface "%s" is already marked as designated master.', has_other_master['.name'])
		end

		o = s:taboption("ipv6", ListValue, "ra", translate('<abbr title="Router Advertisement">RA</abbr>-Service'), translate('Configures the operation mode of the <abbr title="Router Advertisement">RA</abbr> service on this interface.'))
		o:value("", translate("disabled"))
		if net:proto() == "static" then
			o:value("server", translate("server mode"))
		end
		o:value("relay", translate("relay mode"))
		o:value("hybrid", translate("hybrid mode"))

		o = s:taboption("ipv6", ListValue, "dhcpv6", translate("DHCPv6-Service"), translate('Configures the operation mode of the DHCPv6 service on this interface.'))
		o:value("", translate("disabled"))
		if net:proto() == "static" then
			o:value("server", translate("server mode"))
		end
		o:value("relay", translate("relay mode"))
		o:value("hybrid", translate("hybrid mode"))

		o = s:taboption('ipv6', Value, 'dhcpv6_pd_min_len', translate('<abbr title="Prefix Delegation">PD</abbr> minimum length'),
				translate('Configures the minimum delegated prefix length assigned to a requesting downstream router, potentially overriding a requested prefix length. If left unspecified, the device will assign the smallest available prefix greater than or equal to the requested prefix.'))
		o.datatype = 'range(1,62)'
		o:depends({ dhcpv6 = "server" })

		o = s:taboption("ipv6", DynamicList, "dns", translate("Announced IPv6 DNS servers"),
				translate("Specifies a fixed list of IPv6 DNS server addresses to announce via DHCPv6. If left unspecified, the device will announce itself as IPv6 DNS server unless the <em>Local IPv6 DNS server</em> option is disabled."))
		o:depends({ ra = "server", dns_service = false })
		o:depends({ ra = "hybrid", master = false, dns_service = false })
		o:depends({ dhcpv6 = "server", dns_service = false })
		o:depends({ dhcpv6 = "hybrid", master = false, dns_service = false })

		o = s:taboption("ipv6", Flag, "dns_service", translate("Local IPv6 DNS server"),
		        translate("Announce this device as IPv6 DNS server."))
		o.default = o.enabled
		o:depends({ ra = "server" })
		o:depends({ ra = "hybrid", master = false })
		o:depends({ dhcpv6 = "server" })
		o:depends({ dhcpv6 = "hybrid", master = false })

		o = s:taboption("ipv6", DynamicList, "domain", translate("Announced DNS domains"),
				translate("Specifies a fixed list of DNS search domains to announce via DHCPv6. If left unspecified, the local device DNS search domain will be announced."))
		o.datatype = "hostname"
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })
		o:depends("dhcpv6", "server")
		o:depends({ dhcpv6 = "hybrid", master = false })

		o = s:taboption("ipv6", DynamicList, "ntp", translate('NTP Servers'), translate('DHCPv6 option 56.') .. " " .. string.format('<a href="%s" target="_blank">RFC5908</a>', 'https://www.rfc-editor.org/rfc/rfc5908#section-4'))
		local ntp_servers = m.uci:get("system", "ntp", "server")
		for i, v in ipairs(ntp_servers) do
			o:value(v)
		end
		o.optional = true
		o.rmempty = true
		o:depends({ dhcpv6 = "server" })
		o:depends({ dhcpv6 = "hybrid", master = false })

		o = s:taboption("ipv6", ListValue, "ndp", translate('<abbr title="Neighbour Discovery Protocol">NDP</abbr>-Proxy'), translate('Configures the operation mode of the NDP proxy service on this interface.'))
		o:value("", translate("disabled"))
		o:value("relay", translate("relay mode"))
		o:value("hybrid", translate("hybrid mode"))

		o = s:taboption("ipv6", Flag, "ndproxy_routing", translate("Learn routes"),
		        translate("Setup routes for proxied IPv6 neighbours."))
		o.default = o.enabled
		o:depends("ndp", "relay")
		o:depends("ndp", "hybrid")

		o = s:taboption("ipv6", Flag, "ndproxy_slave", translate("NDP-Proxy slave"),
		        translate("Set interface as NDP-Proxy external slave. Default is off."))
		o:depends({ ndp = "relay", master = false })
		o:depends({ ndp = "hybrid", master = false })

		o = s:taboption('ipv6', Value, 'preferred_lifetime', translate('IPv6 Prefix Lifetime'), translate('Preferred lifetime for a prefix.'))
		o.optional = true
		o.default = '12h'
		o:value('5m', translate('5m (5 minutes)'))
		o:value('3h', translate('3h (3 hours)'))
		o:value('12h', translate('12h (12 hours - default)'))
		o:value('7d', translate('7d (7 days)'))

		--This is a ra_* setting, but its placement is more logical/findable under IPv6 settings.
		o = s:taboption('ipv6', Flag, 'ra_useleasetime', translate('Follow IPv4 Lifetime'), translate('DHCPv4 <code>leasetime</code> is used as limit and preferred lifetime of the IPv6 prefix.'))
		o.optional = true

		o = s:taboption("ipv6-ra", ListValue, "ra_default", translate("Default router"),
		        translate('Configures the default router advertisement in <abbr title="Router Advertisement">RA</abbr> messages.'))
		o:value("", translate("automatic"))
		o:value("1", translate("on available prefix"))
		o:value("2", translate("forced"))
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", Flag, "ra_slaac", translate('Enable <abbr title="Stateless Address Auto Config">SLAAC</abbr>'),
		        translate('Set the autonomous address-configuration flag in the prefix information options of sent <abbr title="Router Advertisement">RA</abbr> messages. When enabled, clients will perform stateless IPv6 address autoconfiguration.'))
		o.default = o.enabled
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", MultiValue, "ra_flags", translate('<abbr title="Router Advertisement">RA</abbr> Flags'),
				translate('Specifies the flags sent in <abbr title="Router Advertisement">RA</abbr> messages, for example to instruct clients to request further information via stateful DHCPv6.'))
		o:value("managed-config", translate('managed config (M)'), translate('The <em>Managed address configuration</em> (M) flag indicates that IPv6 addresses are available via DHCPv6.'))
		o:value("other-config", translate('other config (O)'), translate('The <em>Other configuration</em> (O) flag indicates that other information, such as DNS servers, is available via DHCPv6.'))
		o:value("home-agent", translate('mobile home agent (H)'), translate('The <em>Mobile IPv6 Home Agent</em> (H) flag indicates that the device is also acting as Mobile IPv6 home agent on this link.'))
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })
		function o.cfgvalue(self, section)
			local v = ""
			for index, value in ipairs(m2.uci:get("dhcp", section, "ra_flags") or {}) do
				v = v .. " " .. value
			end
			return v
		end

		function o.write(self, section, value)
			m2.uci:delete("dhcp", section, "ra_flags")
			local t = {}
			for v in ut.imatch(value) do
				t[#t + 1] = v
			end
			m2.uci:set("dhcp", section, "ra_flags", t)
		end

		function o.remove(self, section)
			m2.uci:delete("dhcp", section, "ra_flags")
		end

		o = s:taboption('ipv6-ra', Value, 'ra_pref64', translate('NAT64 prefix'), translate('Announce NAT64 prefix in <abbr title="Router Advertisement">RA</abbr> messages.'))
		o.optional = true
		o.datatype = 'cidr6'
		o.placeholder = '64:ff9b::/96'
		o:depends('ra', 'server')
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", Value, "ra_maxinterval", translate('Max <abbr title="Router Advertisement">RA</abbr> interval'),
		        translate('Maximum time allowed between sending unsolicited <abbr title="Router Advertisement, ICMPv6 Type 134">RA</abbr>. Default is 600 seconds.'))
		o.datatype = "uinteger"
		o.placeholder = "600"
		o.default = o.placeholder
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", Value, "ra_mininterval", translate('Min <abbr title="Router Advertisement">RA</abbr> interval'),
		        translate('Minimum time allowed between sending unsolicited <abbr title="Router Advertisement, ICMPv6 Type 134">RA</abbr>. Default is 200 seconds.'))
		o.datatype = "uinteger"
		o.placeholder = "200"
		o.default = o.placeholder
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", Value, "ra_lifetime", translate('<abbr title="Router Advertisement">RA</abbr> Lifetime'),
		        translate('Router Lifetime published in <abbr title="Router Advertisement, ICMPv6 Type 134">RA</abbr> messages. Maximum is 9000 seconds.'))
		o.datatype = "range(0, 9000)"
		o.placeholder = "1800"
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", Value, "ra_mtu", translate('<abbr title="Router Advertisement">RA</abbr> MTU'),
		        translate('The <abbr title="Maximum Transmission Unit">MTU</abbr> to be published in <abbr title="Router Advertisement, ICMPv6 Type 134">RA</abbr> messages. Minimum is 1280 bytes.'))
		o.datatype = "range(1280, 65535)"
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

		o = s:taboption("ipv6-ra", Value, "ra_hoplimit", translate('<abbr title="Router Advertisement">RA</abbr> Hop Limit'),
		        translate('The maximum hops to be published in <abbr title="Router Advertisement">RA</abbr> messages. Maximum is 255 hops.'))
		o.datatype = "range(0, 255)"
		o:depends("ra", "server")
		o:depends({ ra = "hybrid", master = false })

	else
		m2 = nil
	end
end


return m, m2
