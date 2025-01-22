-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local wa = require "luci.tools.webadmin"
local nw = require "luci.model.network"
local ut = require "luci.util"
local nt = require "luci.sys".net
local fs = require "nixio.fs"

arg[1] = arg[1] or ""

m = Map("wireless", "",
	translate("The <em>Device Configuration</em> section covers physical settings of the radio " ..
		"hardware such as channel, transmit power or antenna selection which are shared among all " ..
		"defined wireless networks (if the radio hardware is multi-SSID capable). Per network settings " ..
		"like encryption or operation mode are grouped in the <em>Interface Configuration</em>."))

m:chain("network")
m:chain("firewall")
m.redirect = luci.dispatcher.build_url("admin/network/wireless")

local ifsection

function m.on_commit(map)
	local wnet = nw:get_wifinet(arg[1])
	if ifsection and wnet then
		ifsection.section = wnet.sid
		m.title = luci.util.pcdata(wnet:get_i18n())
	end
end

nw.init(m.uci)

local wnet = nw:get_wifinet(arg[1])
local wdev = wnet and wnet:get_device()

-- redirect to overview page if network does not exist anymore (e.g. after a revert)
if not wnet or not wdev then
	luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless"))
	return
end

-- wireless toggle was requested, commit and reload page
function m.parse(map)
	local new_cc = m:formvalue("cbid.wireless.%s.country" % wdev:name())
	local old_cc = m:get(wdev:name(), "country")

	if m:formvalue("cbid.wireless.%s.__toggle" % wdev:name()) then
		if wdev:get("disabled") == "1" or wnet:get("disabled") == "1" then
			wnet:set("disabled", nil)
		else
			wnet:set("disabled", "1")
		end
		wdev:set("disabled", nil)

		nw:commit("wireless")
		luci.sys.call("(env -i /bin/ubus call network reload) >/dev/null 2>/dev/null")

		luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless", arg[1]))
		return
	end

	Map.parse(map)

	if m:get(wdev:name(), "type") == "mac80211" and new_cc and new_cc ~= old_cc then
		luci.sys.call("iw reg set %s" % ut.shellquote(new_cc))
		luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless", arg[1]))
		return
	end
end

m.title = luci.util.pcdata(wnet:get_i18n())


local function txpower_list(iw)
	local list = iw.txpwrlist or { }
	local off  = tonumber(iw.txpower_offset) or 0
	local new  = { }
	local prev = -1
	local _, val
	for _, val in ipairs(list) do
		local dbm = val.dbm + off
		local mw  = math.floor(10 ^ (dbm / 10))
		if mw ~= prev then
			prev = mw
			new[#new+1] = {
				display_dbm = dbm,
				display_mw  = mw,
				driver_dbm  = val.dbm,
				driver_mw   = val.mw
			}
		end
	end
	return new
end

local function txpower_current(pwr, list)
	pwr = tonumber(pwr)
	if pwr ~= nil then
		local _, item
		for _, item in ipairs(list) do
			if item.driver_dbm >= pwr then
				return item.driver_dbm
			end
		end
	end
	return pwr or ""
end

local iw = luci.sys.wifi.getiwinfo(arg[1])
local hw_modes      = iw.hwmodelist or { }
local tx_power_list = txpower_list(iw)
local tx_power_cur  = txpower_current(wdev:get("txpower"), tx_power_list)

s = m:section(NamedSection, wdev:name(), "wifi-device", translate("Device Configuration"))
s.addremove = false

s:tab("general", translate("General Setup"))
s:tab("macfilter", translate("MAC-Filter"))
s:tab("advanced", translate("Advanced Settings"))

--[[
back = s:option(DummyValue, "_overview", translate("Overview"))
back.value = ""
back.titleref = luci.dispatcher.build_url("admin", "network", "wireless")
]]

st = s:taboption("general", DummyValue, "__status", translate("Status"))
st.template = "admin_network/wifi_status"
st.ifname   = arg[1]

en = s:taboption("general", Button, "__toggle")

if wdev:get("disabled") == "1" or wnet:get("disabled") == "1" then
	en.title      = translate("Wireless network is disabled")
	en.inputtitle = translate("Enable")
	en.inputstyle = "apply"
else
	en.title      = translate("Wireless network is enabled")
	en.inputtitle = translate("Disable")
	en.inputstyle = "reset"
end


local hwtype = wdev:get("type")

-- NanoFoo
local nsantenna = wdev:get("antenna")

-- Check whether there are client interfaces on the same radio,
-- if yes, lock the channel choice as these stations will dicatate the freq
local found_sta = nil
local _, net
if wnet:mode() ~= "sta" then
	for _, net in ipairs(wdev:get_wifinets()) do
		if net:mode() == "sta" and net:get("disabled") ~= "1" then
			if not found_sta then
				found_sta = {}
				found_sta.channel = net:channel()
				found_sta.names = {}
			end
			found_sta.names[#found_sta.names+1] = net:shortname()
		end
	end
end

if found_sta then
	ch = s:taboption("general", DummyValue, "choice", translate("Channel"))
	ch.value = translatef("Locked to channel %s used by: %s",
		found_sta.channel or "(auto)", table.concat(found_sta.names, ", "))
else
	ch = s:taboption("general", Value, "_mode_freq", '<br />'..translate("Operating frequency"))
	ch.hwmodes = hw_modes
	ch.htmodes = iw.htmodelist
	ch.freqlist = iw.freqlist
	local has_band = ut.exec("[ -s /lib/wifi/mac80211.uc ] && cat /lib/wifi/mac80211.uc 2>/dev/null")
	if not has_band or has_band == "" then
		has_band = ut.exec("[ -s /lib/wifi/mac80211.sh ] && cat /lib/wifi/mac80211.sh 2>/dev/null | grep 'get_band_defaults'")
	end
	ch.has_band = (has_band and has_band ~= "") and true or false
	ch.template = "cbi/wireless_modefreq"

	function ch.cfgvalue(self, section)
		local band = "hwmode"
		if self.has_band then
			band = "band"
		end
		return {
			m:get(section, band) or "",
			m:get(section, "channel") or "auto",
			m:get(section, "htmode") or ""
		}
	end

	function ch.formvalue(self, section)
		local band = m:formvalue(self:cbid(section) .. ".band")
		if not band then
			if hw_modes.g then
				band = "11g"
			else
				band = "11a"
			end
			if self.has_band then
				if hw_modes.g then
					band = "2g"
				else
					band = "5g"
				end
			end
		end
		return {
			band,
			m:formvalue(self:cbid(section) .. ".channel") or "auto",
			m:formvalue(self:cbid(section) .. ".htmode") or ""
		}
	end

	function ch.write(self, section, value)
		if self.has_band then
			m:set(section, "band", value[1])
		else
			if value[1] == "2g" then
				m:set(section, "hwmode", "11g")
			elseif value[1] == "5g" then
				m:set(section, "hwmode", "11a")
			end
		end
		m:set(section, "channel", value[2])
		m:set(section, "htmode", value[3])
	end
end

------------------- MAC80211 Device ------------------

if hwtype == "mac80211" then
	if hw_modes.b or hw_modes.g then
		legacyrates = s:taboption("general", Flag, "legacy_rates", translate("Allow legacy 802.11b rates"),
			translate("Legacy or badly behaving devices may require legacy 802.11b rates to interoperate. Airtime efficiency may be significantly reduced where these are used. It is recommended to not allow 802.11b rates where possible."))
		legacyrates.rmempty = false
		legacyrates.default = "1"
	end

	if #tx_power_list > 0 then
		tp = s:taboption("general", ListValue,
			"txpower", translate("Maximum transmit power"),
			translate("Specifies the maximum transmit power the wireless radio may use. Depending on regulatory requirements and wireless usage, the actual transmit power may be reduced by the driver."))
		tp.rmempty = true
		tp.default = tx_power_cur
		function tp.cfgvalue(...)
			return txpower_current(Value.cfgvalue(...), tx_power_list)
		end

		tp:value("", translate("auto"))
		for _, p in ipairs(tx_power_list) do
			tp:value(p.driver_dbm, "%i dBm (%i mW)"
				%{ p.display_dbm, p.display_mw })
		end
	end

	local cl = iw and iw.countrylist
	if cl and #cl > 0 then
		cc = s:taboption("general", ListValue, "country", translate("Country Code"))
		cc.default = tostring(iw and iw.country or "00")
		for _, c in ipairs(cl) do
			cc:value(c.alpha2, "%s - %s" %{ c.alpha2, c.name })
		end
	else
		s:taboption("general", Value, "country", translate("Country Code"), translate("Use ISO/IEC 3166 alpha2 country codes."))
	end

	o = s:taboption("advanced", ListValue, "cell_density", translate("Coverage cell density"),
		translate('Configures data rates based on the coverage cell density. Normal configures basic rates to 6, 12, 24 Mbps if legacy 802.11b rates are not used else to 5.5, 11 Mbps. High configures basic rates to 12, 24 Mbps if legacy 802.11b rates are not used else to the 11 Mbps rate. Very High configures 24 Mbps as the basic rate. Supported rates lower than the minimum basic rate are not offered.'))
	o:value('0', translate('Disabled'))
	o:value('1', translate('Normal'))
	o:value('2', translate('High'))
	o:value('3', translate('Very High'))

	o = s:taboption("advanced", Value, "distance", translate("Distance Optimization"),
			translate("Distance to farthest network member in meters. Set only for distances above one kilometer; otherwise it is harmful."))
	o.datatype = 'or(range(0,114750),"auto")'
	o.placeholder = 'auto'

	-- external antenna profiles
	local eal = iw and iw.extant
	if eal and #eal > 0 then
		ea = s:taboption("advanced", ListValue, "extant", translate("Antenna Configuration"))
		for _, eap in ipairs(eal) do
			ea:value(eap.id, "%s (%s)" %{ eap.name, eap.description })
			if eap.selected then
				ea.default = eap.id
			end
		end
	end

	o = s:taboption("advanced", Value, "frag", translate("Fragmentation Threshold"))
	o.datatype = 'min(256)'
	o.placeholder = translate('off')

	o = s:taboption("advanced", Value, "rts", translate("RTS/CTS Threshold"))
	o.datatype = 'uinteger'
	o.placeholder = translate('off')

	noscan = s:taboption("advanced", Flag, "noscan", translate("Force 40MHz mode"),
		translate("Always use 40MHz channels even if the secondary channel overlaps. Using this option does not comply with IEEE 802.11n-2009!"))
	noscan.default = noscan.disabled

	o = s:taboption("advanced", Value, "beacon_int", translate("Beacon Interval"))
	o.datatype = 'range(15,65535)'
	o.placeholder = '100'
	o.rmempty = true
	
	if hw_modes.b or hw_modes.g then
		vendor_vht = s:taboption("advanced", Flag, "vendor_vht", translate("Enable 256-QAM"))
		vendor_vht.default = vendor_vht.disabled
	end

	mubeamformer = s:taboption("advanced", Flag, "mu_beamformer", translate("MU-MIMO"))
	mubeamformer.rmempty = false
	mubeamformer.default = "0"
end


------------------- Broadcom Device ------------------

if hwtype == "broadcom" then
	tp = s:taboption("general",
		(#tx_power_list > 0) and ListValue or Value,
		"txpower", translate("Transmit Power"), "dBm")

	tp.rmempty = true
	tp.default = tx_power_cur

	function tp.cfgvalue(...)
		return txpower_current(Value.cfgvalue(...), tx_power_list)
	end

	tp:value("", translate("auto"))
	for _, p in ipairs(tx_power_list) do
		tp:value(p.driver_dbm, "%i dBm (%i mW)"
			%{ p.display_dbm, p.display_mw })
	end

	mode = s:taboption("advanced", ListValue, "hwmode", translate("Band"))
	if hw_modes.b then
		mode:value("11b", "2.4GHz (802.11b)")
		if hw_modes.g then
			mode:value("11bg", "2.4GHz (802.11b+g)")
		end
	end
	if hw_modes.g then
		mode:value("11g", "2.4GHz (802.11g)")
		mode:value("11gst", "2.4GHz (802.11g + Turbo)")
		mode:value("11lrs", "2.4GHz (802.11g Limited Rate Support)")
	end
	if hw_modes.a then mode:value("11a", "5GHz (802.11a)") end
	if hw_modes.n then
		if hw_modes.g then
			mode:value("11ng", "2.4GHz (802.11g+n)")
			mode:value("11n", "2.4GHz (802.11n)")
		end
		if hw_modes.a then
			mode:value("11na", "5GHz (802.11a+n)")
			mode:value("11n", "5GHz (802.11n)")
		end
		htmode = s:taboption("advanced", ListValue, "htmode", translate("HT mode (802.11n)"))
		htmode:depends("hwmode", "11ng")
		htmode:depends("hwmode", "11na")
		htmode:depends("hwmode", "11n")
		htmode:value("HT20", "20MHz")
		htmode:value("HT40", "40MHz")
	end

	ant1 = s:taboption("advanced", ListValue, "txantenna", translate("Transmitter Antenna"))
	ant1.widget = "radio"
	ant1:depends("diversity", "")
	ant1:value("3", translate("auto"))
	ant1:value("0", translate("Antenna 1"))
	ant1:value("1", translate("Antenna 2"))

	ant2 = s:taboption("advanced", ListValue, "rxantenna", translate("Receiver Antenna"))
	ant2.widget = "radio"
	ant2:depends("diversity", "")
	ant2:value("3", translate("auto"))
	ant2:value("0", translate("Antenna 1"))
	ant2:value("1", translate("Antenna 2"))

	s:taboption("advanced", Flag, "frameburst", translate("Frame Bursting"))

	o = s:taboption("advanced", Value, "distance", translate("Distance Optimization"),
			translate("Distance to farthest network member in meters. Set only for distances above one kilometer; otherwise it is harmful."))
	o.datatype = 'or(range(0,114750),"auto")'
	o.placeholder = 'auto'

	--s:option(Value, "slottime", translate("Slot time"))

	s:taboption("general", Value, "country", translate("Country Code"), translate("Use ISO/IEC 3166 alpha2 country codes."))
	s:taboption("advanced", Value, "maxassoc", translate("Connection Limit"))
end


--------------------- HostAP Device ---------------------

if hwtype == "prism2" then
	s:taboption("advanced", Value, "txpower", translate("Transmit Power"), "att units").rmempty = true

	s:taboption("advanced", Flag, "diversity", translate("Diversity")).rmempty = false

	s:taboption("advanced", Value, "txantenna", translate("Transmitter Antenna"))
	s:taboption("advanced", Value, "rxantenna", translate("Receiver Antenna"))
end


----------------------- Interface -----------------------

s = m:section(NamedSection, wnet.sid, "wifi-iface", translate("Interface Configuration"))
ifsection = s
s.addremove = false
s.anonymous = true
s.defaults.device = wdev:name()

s:tab("general", translate("General Setup"))
s:tab("encryption", translate("Wireless Security"))
s:tab("macfilter", translate("MAC-Filter"))
s:tab("advanced", translate("Advanced Settings"))
s:tab("roaming", translate("WLAN roaming"), translate('Settings for assisting wireless clients in roaming between multiple APs: 802.11r, 802.11k and 802.11v'))

mode = s:taboption("general", ListValue, "mode", translate("Mode"))
mode.override_values = true
mode:value("ap", translate("Access Point"))
mode:value("sta", translate("Client"))
mode:value("adhoc", translate("Ad-Hoc"))

meshid = s:taboption("general", Value, "mesh_id", translate("Mesh Id"))
meshid:depends({mode="mesh"})

meshfwd = s:taboption("advanced", Flag, "mesh_fwding", translate("Forward mesh peer traffic"))
meshfwd.rmempty = false
meshfwd.default = "1"
meshfwd:depends({mode="mesh"})

mesh_rssi_threshold = s:taboption("advanced", Flag, "mesh_rssi_threshold", translate("RSSI threshold for joining"), translate('0 = not using RSSI threshold, 1 = do not change driver default'))
mesh_rssi_threshold.rmempty = false
mesh_rssi_threshold.default = "0"
mesh_rssi_threshold.datatype = 'range(-255,1)'
mesh_rssi_threshold:depends({mode="mesh"})

ssid = s:taboption("general", Value, "ssid", translate("<abbr title=\"Extended Service Set Identifier\">ESSID</abbr>"))
ssid.datatype = "maxlength(32)"
ssid:depends({mode="ap"})
ssid:depends({mode="sta"})
ssid:depends({mode="adhoc"})
ssid:depends({mode="ahdemo"})
ssid:depends({mode="monitor"})
ssid:depends({mode="ap-wds"})
ssid:depends({mode="sta-wds"})
ssid:depends({mode="wds"})

bssid = s:taboption("general", Value, "bssid", translate("<abbr title=\"Basic Service Set Identifier\">BSSID</abbr>"))

network = s:taboption("general", Value, "network", translate("Network"),
	translate("Choose the network(s) you want to attach to this wireless interface or " ..
		"fill out the <em>create</em> field to define a new network."))

network.rmempty = true
network.template = "cbi/network_netlist"
network.widget = "checkbox"
network.novirtual = true

function network.write(self, section, value)
	local i = nw:get_interface(section)
	if i then
		if value == '-' then
			value = m:formvalue(self:cbid(section) .. ".newnet")
			if value and #value > 0 then
				local n = nw:add_network(value, {proto="none"})
				if n then n:add_interface(i) end
			else
				local n = i:get_network()
				if n then n:del_interface(i) end
			end
		else
			local v
			for _, v in ipairs(i:get_networks()) do
				v:del_interface(i)
			end
			for v in ut.imatch(value) do
				local n = nw:get_network(v)
				if n then
					if not nw.new_netifd and not n:is_empty() then
						n:set("type", "bridge")
					end
					n:add_interface(i)
				end
			end
		end
	end
end

-------------------- MAC80211 Interface ----------------------

if hwtype == "mac80211" then
	if fs.access("/usr/sbin/iw") then
		mode:value("mesh", "802.11s")
	end

	mode:value("ahdemo", translate("Pseudo Ad-Hoc (ahdemo)"))
	mode:value("monitor", translate("Monitor"))
	bssid:depends({mode="adhoc"})
	bssid:depends({mode="sta"})
	bssid:depends({mode="sta-wds"})

	mp = s:taboption("macfilter", ListValue, "macfilter", translate("MAC-Address Filter"))
	mp:depends({mode="ap"})
	mp:depends({mode="ap-wds"})
	mp:value("", translate("disable"))
	mp:value("allow", translate("Allow listed only"))
	mp:value("deny", translate("Allow all except listed"))

	ml = s:taboption("macfilter", DynamicList, "maclist", translate("MAC-List"))
	ml.datatype = "macaddr"
	ml:depends({macfilter="allow"})
	ml:depends({macfilter="deny"})
	nt.mac_hints(function(mac, name) ml:value(mac, "%s (%s)" %{ mac, name }) end)

	mode:value("ap-wds", "%s (%s)" % {translate("Access Point"), translate("WDS")})
	mode:value("sta-wds", "%s (%s)" % {translate("Client"), translate("WDS")})

	function mode.write(self, section, value)
		if value == "ap-wds" then
			ListValue.write(self, section, "ap")
			m.uci:set("wireless", section, "wds", 1)
		elseif value == "sta-wds" then
			ListValue.write(self, section, "sta")
			m.uci:set("wireless", section, "wds", 1)
		else
			ListValue.write(self, section, value)
			m.uci:delete("wireless", section, "wds")
		end
	end

	function mode.cfgvalue(self, section)
		local mode = ListValue.cfgvalue(self, section)
		local wds  = m.uci:get("wireless", section, "wds") == "1"

		if mode == "ap" and wds then
			return "ap-wds"
		elseif mode == "sta" and wds then
			return "sta-wds"
		else
			return mode
		end
	end

	hidden = s:taboption("general", Flag, "hidden", translate("Hide <abbr title=\"Extended Service Set Identifier\">ESSID</abbr>"), translate('Where the ESSID is hidden, clients may fail to roam and airtime efficiency may be significantly reduced.'))
	hidden:depends({mode="ap"})
	hidden:depends({mode="ap-wds"})

	wmm = s:taboption("general", Flag, "wmm", translate("WMM Mode"), translate('Where Wi-Fi Multimedia (WMM) Mode QoS is disabled, clients may be limited to 802.11a/802.11g rates.'))
	wmm:depends({mode="ap"})
	wmm:depends({mode="ap-wds"})
	wmm.default = wmm.enabled

	o = s:taboption("advanced", Flag, "multicast_to_unicast_all", translate("Multi To Unicast"), translate('ARP, IPv4 and IPv6 (even 802.1Q) with multicast destination MACs are unicast to the STA MAC address. Note: This is not Directed Multicast Service (DMS) in 802.11v. Note: might break receiver STA multicast expectations.'))
	o.rmempty = true

	isolate = s:taboption("advanced", Flag, "isolate", translate("Isolate Clients"),
	 translate("Prevents client-to-client communication"))
	isolate:depends({mode="ap"})
	isolate:depends({mode="ap-wds"})

	ifname = s:taboption("advanced", Value, "ifname", translate("Interface name"), translate("Override default interface name"))
	ifname.optional = true

	-- Need optimization
	o = s:taboption("advanced", Value, "macaddr", translate("MAC address"), translate('Override default MAC address - the range of usable addresses might be limited by the driver'))
	o:value("", translate('driver default'))
	o:value("random", translate('randomly generated'))
	o.datatype = "or('random',macaddr)"

	o = s:taboption("advanced", Flag, "short_preamble", translate("Short Preamble"))
	o.default = o.enabled

	o = s:taboption("advanced", Value, "dtim_period", translate("DTIM Interval"), translate('Delivery Traffic Indication Message Interval'))
	o.optional = true
	o.placeholder = 2
	o.datatype = 'range(1,255)'

	o = s:taboption("advanced", Value, "wpa_group_rekey", translate("Time interval for rekeying GTK"), translate('sec'))
	o.optional = true
	o.placeholder = 600
	o.datatype = 'uinteger'

	o = s:taboption("advanced", Flag, "skip_inactivity_poll", translate("Disable Inactivity Polling"))
	o.optional = true
	o.datatype = 'uinteger'

	o = s:taboption("advanced", Value, "max_inactivity", translate("Station inactivity limit"), translate('802.11v: BSS Max Idle. Units: seconds.'))
	o.optional = true
	o.placeholder = 300
	o.datatype = 'uinteger'

	o = s:taboption("advanced", Value, "max_listen_interval", translate("Maximum allowed Listen Interval"))
	o.optional = true
	o.placeholder = 65535
	o.datatype = 'uinteger'

	o = s:taboption("advanced", Flag, "disassoc_low_ack", translate("Disassociate On Low Acknowledgement"), translate('Allow AP mode to disconnect STAs based on low ACK condition'))
	o.default = o.enabled
end


-------------------- Broadcom Interface ----------------------

if hwtype == "broadcom" then
	mode:value("wds", translate("WDS"))
	mode:value("monitor", translate("Monitor"))

	hidden = s:taboption("general", Flag, "hidden", translate("Hide <abbr title=\"Extended Service Set Identifier\">ESSID</abbr>"), translate('Where the ESSID is hidden, clients may fail to roam and airtime efficiency may be significantly reduced.'))
	hidden:depends({mode="ap"})
	hidden:depends({mode="adhoc"})
	hidden:depends({mode="wds"})

	isolate = s:taboption("advanced", Flag, "isolate", translate("Separate Clients"),
	 translate("Prevents client-to-client communication"))
	isolate:depends({mode="ap"})

	s:taboption("advanced", Flag, "doth", "802.11h")
	s:taboption("advanced", Flag, "wmm", translate("WMM Mode"), translate('Where Wi-Fi Multimedia (WMM) Mode QoS is disabled, clients may be limited to 802.11a/802.11g rates.'))

	bssid:depends({mode="wds"})
	bssid:depends({mode="adhoc"})
end


----------------------- HostAP Interface ---------------------

if hwtype == "prism2" then
	mode:value("wds", translate("WDS"))
	mode:value("monitor", translate("Monitor"))

	hidden = s:taboption("general", Flag, "hidden", translate("Hide <abbr title=\"Extended Service Set Identifier\">ESSID</abbr>"), translate('Where the ESSID is hidden, clients may fail to roam and airtime efficiency may be significantly reduced.'))
	hidden:depends({mode="ap"})
	hidden:depends({mode="adhoc"})
	hidden:depends({mode="wds"})

	bssid:depends({mode="sta"})

	mp = s:taboption("macfilter", ListValue, "macpolicy", translate("MAC-Address Filter"))
	mp:value("", translate("disable"))
	mp:value("allow", translate("Allow listed only"))
	mp:value("deny", translate("Allow all except listed"))
	ml = s:taboption("macfilter", DynamicList, "maclist", translate("MAC-List"))
	ml:depends({macpolicy="allow"})
	ml:depends({macpolicy="deny"})
	nt.mac_hints(function(mac, name) ml:value(mac, "%s (%s)" %{ mac, name }) end)

	s:taboption("advanced", Value, "rate", translate("Transmission Rate"))

	o = s:taboption("advanced", Value, "frag", translate("Fragmentation Threshold"))
	o.datatype = 'min(256)'
	o.placeholder = translate('off')

	o = s:taboption("advanced", Value, "rts", translate("RTS/CTS Threshold"))
	o.datatype = 'uinteger'
	o.placeholder = translate('off')
end


------------------- WiFI-Encryption -------------------

encr = s:taboption("encryption", ListValue, "encryption", translate("Encryption"))
encr.override_values = true
encr.override_depends = true
encr:depends({mode="ap"})
encr:depends({mode="sta"})
encr:depends({mode="adhoc"})
encr:depends({mode="ahdemo"})
encr:depends({mode="ap-wds"})
encr:depends({mode="sta-wds"})
encr:depends({mode="mesh"})

cipher = s:taboption("encryption", ListValue, "cipher", translate("Cipher"))
cipher:depends({encryption="wpa"})
cipher:depends({encryption="wpa2"})
cipher:depends({encryption="wpa3"})
cipher:depends({encryption="wpa3-mixed"})
cipher:depends({encryption="wpa3-192"})
cipher:depends({encryption="psk"})
cipher:depends({encryption="psk2"})
cipher:depends({encryption="wpa-mixed"})
cipher:depends({encryption="psk-mixed"})
cipher:value("auto", translate("auto"))
cipher:value("ccmp", translate("Force CCMP (AES)"))
cipher:value("ccmp256", translate("Force CCMP-256 (AES)"))
cipher:value("gcmp", translate("Force GCMP (AES)"))
cipher:value("gcmp256", translate("Force GCMP-256 (AES)"))
cipher:value("tkip", translate("Force TKIP"))
cipher:value("tkip+ccmp", translate("Force TKIP and CCMP (AES)"))

function encr.cfgvalue(self, section)
	local v = tostring(ListValue.cfgvalue(self, section))
	if v == "wep" then
		return "wep-open"
	elseif v and v:match("%+") then
		return (v:gsub("%+.+$", ""))
	end
	return v
end

function encr.write(self, section, value)
	local e = tostring(encr:formvalue(section))
	local c = tostring(cipher:formvalue(section))
	if value == "wpa" or value == "wpa2"  then
		self.map.uci:delete("wireless", section, "key")
	end
	if e and (c == "tkip" or c == "ccmp" or c == "tkip+ccmp") then
		e = e .. "+" .. c
	end
	self.map:set(section, "encryption", e)
end

function cipher.cfgvalue(self, section)
	local v = tostring(ListValue.cfgvalue(encr, section))
	if v and v:match("%+") then
		v = v:gsub("^[^%+]+%+", "")
		if v == "aes" then v = "ccmp"
		elseif v == "tkip+aes" then v = "tkip+ccmp"
		elseif v == "aes+tkip" then v = "tkip+ccmp"
		elseif v == "ccmp+tkip" then v = "tkip+ccmp"
		end
	end
	return v
end

function cipher.write(self, section)
	return encr:write(section)
end

local crypto_modes = {}
if hwtype == "mac80211" or hwtype == "prism2" then
	local supplicant = fs.access("/usr/sbin/wpa_supplicant")
	local hostapd = fs.access("/usr/sbin/hostapd")

	local has_supplicant = fs.access("/usr/sbin/wpa_supplicant")
	local has_hostapd = fs.access("/usr/sbin/hostapd")

	-- Probe EAP support
	local has_ap_eap  = (os.execute("hostapd -veap >/dev/null 2>/dev/null") == 0)
	local has_sta_eap = (os.execute("wpa_supplicant -veap >/dev/null 2>/dev/null") == 0)
	
	-- Probe SAE support
	local has_ap_sae  = (os.execute("hostapd -vsae >/dev/null 2>/dev/null") == 0)
	local has_sta_sae = (os.execute("wpa_supplicant -vsae >/dev/null 2>/dev/null") == 0)

	-- Probe OWE support
	local has_ap_owe  = (os.execute("hostapd -vowe >/dev/null 2>/dev/null") == 0)
	local has_sta_owe = (os.execute("wpa_supplicant -vowe >/dev/null 2>/dev/null") == 0)

	-- Probe Suite-B support
	local has_ap_eap192  = (os.execute("hostapd -vsuiteb192 >/dev/null 2>/dev/null") == 0)
	local has_sta_eap192 = (os.execute("wpa_supplicant -vsuiteb192 >/dev/null 2>/dev/null") == 0)

	-- Probe WEP support
	local has_ap_wep  = (os.execute("hostapd -vwep >/dev/null 2>/dev/null") == 0)
	local has_sta_wep = (os.execute("wpa_supplicant -vwep >/dev/null 2>/dev/null") == 0)

	if has_hostapd or has_supplicant then
		crypto_modes[#crypto_modes + 1] = {"psk2", "WPA2-PSK", 35}
		crypto_modes[#crypto_modes + 1] = {"psk-mixed", "WPA-PSK/WPA2-PSK Mixed Mode", 22}
		crypto_modes[#crypto_modes + 1] = {"psk", "WPA-PSK", 12}
	else
		encr.description = translate('WPA-Encryption requires wpa_supplicant (for client mode) or hostapd (for AP and ad-hoc mode) to be installed.')
	end

	if has_ap_sae or has_sta_sae then
		crypto_modes[#crypto_modes + 1] = {"sae", "WPA3-SAE", 31}
		crypto_modes[#crypto_modes + 1] = {"sae-mixed", "WPA2-PSK/WPA3-SAE Mixed Mode", 30}
	end

	if has_ap_wep or has_sta_wep then
		crypto_modes[#crypto_modes + 1] = {"wep-open", translate("WEP Open System"), 11}
		crypto_modes[#crypto_modes + 1] = {"wep-shared", translate("WEP Shared Key"), 10}
	end

	if has_ap_eap or has_sta_eap then
		if has_ap_eap192 or has_sta_eap192 then
			crypto_modes[#crypto_modes + 1] = {"wpa3", "WPA3-EAP", 33}
			crypto_modes[#crypto_modes + 1] = {"wpa3-mixed", "WPA2-EAP/WPA3-EAP Mixed Mode", 32}
			crypto_modes[#crypto_modes + 1] = {"wpa3-192", "WPA3-EAP 192-bit Mode", 36}
		end
		crypto_modes[#crypto_modes + 1] = {"wpa2", "WPA2-EAP", 34}
		crypto_modes[#crypto_modes + 1] = {"wpa", "WPA-EAP", 20}
	end

	if has_ap_owe or has_sta_owe then
		crypto_modes[#crypto_modes + 1] = {"owe", translate("OWE"), 1}
	end

	local crypto_support = {
		ap = {
			["wep-open"] = has_ap_wep or translate('Requires hostapd with WEP support'),
			["wep-shared"] = has_ap_wep or translate('Requires hostapd with WEP support'),
			["psk"] = has_hostapd or translate('Requires hostapd'),
			["psk2"] = has_hostapd or translate('Requires hostapd'),
			["psk-mixed"] = has_hostapd or translate('Requires hostapd'),
			["sae"] = has_ap_sae or translate('Requires hostapd with SAE support'),
			["sae-mixed"] = has_ap_sae or translate('Requires hostapd with SAE support'),
			["wpa"] = has_ap_eap or translate('Requires hostapd with EAP support'),
			["wpa2"] = has_ap_eap or translate('Requires hostapd with EAP support'),
			["wpa3"] = has_ap_eap192 or translate('Requires hostapd with EAP Suite-B support'),
			["wpa3-mixed"] = has_ap_eap192 or translate('Requires hostapd with EAP Suite-B support'),
			["wpa3-192"] = has_ap_eap192 or translate('Requires hostapd with EAP Suite-B support'),
			["owe"] = has_ap_owe or translate('Requires hostapd with OWE support')
		},
		sta = {
			["wep-open"] = has_sta_wep or translate('Requires wpa-supplicant with WEP support'),
			["wep-shared"] = has_sta_wep or translate('Requires wpa-supplicant with WEP support'),
			["psk"] = has_supplicant or translate('Requires wpa-supplicant'),
			["psk2"] = has_supplicant or translate('Requires wpa-supplicant'),
			["psk-mixed"] = has_supplicant or translate('Requires wpa-supplicant'),
			["sae"] = has_sta_sae or translate('Requires wpa-supplicant with SAE support'),
			["sae-mixed"] = has_sta_sae or translate('Requires wpa-supplicant with SAE support'),
			["wpa"] = has_sta_eap or translate('Requires wpa-supplicant with EAP support'),
			["wpa2"] = has_sta_eap or translate('Requires wpa-supplicant with EAP support'),
			["wpa3"] = has_sta_eap192 or translate('Requires wpa-supplicant with EAP Suite-B support'),
			["wpa3-mixed"] = has_sta_eap192 or translate('Requires wpa-supplicant with EAP Suite-B support'),
			["wpa3-192"] = has_sta_eap192 or translate('Requires wpa-supplicant with EAP Suite-B support'),
			["owe"] = has_sta_owe or translate('Requires wpa-supplicant with OWE support')
		},
		adhoc = {
			["wep-open"] = true,
			["wep-shared"] = true,
			["psk"] = has_supplicant or translate('Requires wpa-supplicant'),
			["psk2"] = has_supplicant or translate('Requires wpa-supplicant'),
			["psk-mixed"] = has_supplicant or translate('Requires wpa-supplicant')
		},
		mesh = {
			["sae"] = has_sta_sae or translate('Requires wpa-supplicant with SAE support')
		},
		ahdemo = {
			["wep-open"] = true,
			["wep-shared"] = true
		},
		wds = {
			["wep-open"] = true,
			["wep-shared"] = true
		}
	}
	crypto_support['ap-wds'] = crypto_support['ap']
	crypto_support['sta-wds'] = crypto_support['sta']
elseif hwtype == "broadcom" then
	crypto_modes[#crypto_modes + 1] = {"psk2", "WPA2-PSK", 33}
	crypto_modes[#crypto_modes + 1] = {"psk+psk2", "WPA-PSK/WPA2-PSK Mixed Mode", 22}
	crypto_modes[#crypto_modes + 1] = {"psk", "WPA-PSK", 12}
	crypto_modes[#crypto_modes + 1] = {"wep-open", translate("WEP Open System"), 11}
	crypto_modes[#crypto_modes + 1] = {"wep-shared", translate("WEP Shared Key"), 10}
end

crypto_modes[#crypto_modes + 1] = {"none", translate("No Encryption"), 0}

table.sort(crypto_modes, function(a, b)
	return b[3] < a[3]
end)

for i, v in ipairs(crypto_modes) do
	local security_level = ""
	if crypto_modes[i][3] >= 30 then
		security_level = translate("strong security")
	elseif crypto_modes[i][3] >= 20 then
		security_level = translate("medium security")
	elseif crypto_modes[i][3] >= 10 then
		security_level = translate("weak security")
	else
		security_level = translate("open network")
	end
	encr:value(crypto_modes[i][1], string.format("%s (%s)", crypto_modes[i][2], security_level))
end

o = s:taboption("encryption", Flag, "ppsk", translate("Enable Private PSK (PPSK)"), translate('Private Pre-Shared Key (PPSK) allows the use of different Pre-Shared Key for each STA MAC address. Private MAC PSKs are stored on the RADIUS server.'))
o:depends({mode="ap", encryption="psk"})
o:depends({mode="ap", encryption="psk2"})
o:depends({mode="ap", encryption="psk+psk2"})
o:depends({mode="ap", encryption="psk-mixed"})
o:depends({mode="ap-wds", encryption="psk"})
o:depends({mode="ap-wds", encryption="psk2"})
o:depends({mode="ap-wds", encryption="psk+psk2"})
o:depends({mode="ap-wds", encryption="psk-mixed"})

o = s:taboption("encryption", Value, "auth_server", translate("RADIUS Authentication Server"))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})
o.rmempty = true
o.datatype = "host(0)"

o = s:taboption("encryption", Value, "auth_port", translate("RADIUS Authentication Port"))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})
o.rmempty = true
o.datatype = "port"
o.placeholder = "1812"
o.default = o.placeholder

o = s:taboption("encryption", Value, "auth_secret", translate("RADIUS Authentication Secret"))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})
o.rmempty = true
o.password = true

o = s:taboption("encryption", Value, "acct_server", translate("RADIUS Accounting Server"))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.datatype = "host(0)"

o = s:taboption("encryption", Value, "acct_port", translate("RADIUS Accounting Port"))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.datatype = "port"
o.placeholder = "1813"
o.default = o.placeholder

o = s:taboption("encryption", Value, "acct_secret", translate("RADIUS Accounting Secret"))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.password = true

-- extra RADIUS settings start
local attr_validate = function(self, value)
	if not value then
		return true
	end
	if not string.match(value, "^[0-9]+(:s:.+|:d:[0-9]+|:x:([0-9a-zA-Z][0-9a-zA-Z])*)?$") then
		return translatef('Must be in %s format.', '<attr_id>[:<syntax:value>]')
	end
	return true
end

-- https://w1.fi/cgit/hostap/commit/?id=af35e7af7f8bb1ca9f0905b4074fb56a264aa12b
local req_attr_syntax = translate('Format') .. '<code>&lt;attr_id&gt;[:&lt;syntax:value&gt;]</code>' .. '<br />' ..
	translatef('<code>syntax: s = %s; ', translatef('string (UTF-8)') .. translatef('d = %s; ', translate("integer")) .. translate('x = %s</code>', translate('octet string')))
o = s:taboption("encryption", DynamicList, "radius_auth_req_attr", translate("RADIUS Access-Request attributes"), translate("Attributes to add/replace in each request.") .. "<br />" .. req_attr_syntax)
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.validate = attr_validate
o.placeholder = '126:s:Operator'

o = s:taboption("encryption", DynamicList, "radius_acct_req_attr", translate("RADIUS Accounting-Request attributes"), translate("Attributes to add/replace in each request.") .. "<br />" .. req_attr_syntax)
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.validate = attr_validate
o.placeholder = '77:x:74657374696e67'

o = s:taboption("encryption", ListValue, "dynamic_vlan", translate("RADIUS Dynamic VLAN Assignment"), translate("Required: Rejects auth if RADIUS server does not provide appropriate VLAN attributes."))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})
o:value("0", translate("Disabled"))
o:value("1", translate("Optional"))
o:value("2", translate("Required"))
o.write = function(self, section, value)
	if value == "0" then
		return Value.remove(self, section)
	else
		return Value.write(self, section, value)
	end
end

o = s:taboption("encryption", Flag, "per_sta_vif", translate("RADIUS Per STA VLAN"), translate("Each STA is assigned its own AP_VLAN interface."))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})

-- hostapd internally defaults to vlan_naming=1 even with dynamic VLAN off
o = s:taboption("encryption", Flag, "vlan_naming", translate("RADIUS VLAN Naming"), translate('Off: <code>vlanXXX</code>, e.g., <code>vlan1</code>. On: <code>vlan_tagged_interface.XXX</code>, e.g. <code>eth0.1</code>.'))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})

-- Need optimization
o = s:taboption("encryption", Value, "vlan_tagged_interface", translate("RADIUS VLAN Tagged Interface"), translate('E.g. eth0, eth1'))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})
o.rmempty = true

o = s:taboption("encryption", Value, "vlan_bridge", translate("RADIUS VLAN Bridge Naming Scheme"), translate('E.g. <code>br-vlan</code> or <code>brvlan</code>.'))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o:depends({mode="ap", encryption="psk", ppsk=true})
o:depends({mode="ap", encryption="psk2", ppsk=true})
o:depends({mode="ap", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap", encryption="psk-mixed", ppsk=true})
o:depends({mode="ap-wds", encryption="psk", ppsk=true})
o:depends({mode="ap-wds", encryption="psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk+psk2", ppsk=true})
o:depends({mode="ap-wds", encryption="psk-mixed", ppsk=true})
o.rmempty = true

-- extra RADIUS settings end

o = s:taboption("encryption", Value, "dae_client", translate("DAE-Client"), translate('Dynamic Authorization Extension client.'))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.datatype = "host(0)"

o = s:taboption("encryption", Value, "dae_port", translate("DAE-Port"), translate('Dynamic Authorization Extension port.'))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.datatype = "port"
o.placeholder = "3799"

o = s:taboption("encryption", Value, "dae_secret", translate("DAE-Secret"), translate('Dynamic Authorization Extension secret.'))
o:depends({mode="ap", encryption="wpa"})
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap", encryption="wpa3-192"})
o:depends({mode="ap-wds", encryption="wpa"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa3-192"})
o.rmempty = true
o.password = true

-- WPA(1) has only WPA IE. Only >= WPA2 has RSN IE Preauth frames.
o = s:taboption("encryption", Flag, "rsn_preauth", translate("RSN Preauth"), translate('Robust Security Network (RSN): Allow roaming preauth for WPA2-EAP networks (and advertise it in WLAN beacons). Only works if the specified network interface is a bridge. Shortens the time-critical reassociation process.'))
o:depends({mode="ap", encryption="wpa2"})
o:depends({mode="ap", encryption="wpa3"})
o:depends({mode="ap", encryption="wpa3-mixed"})
o:depends({mode="ap-wds", encryption="wpa2"})
o:depends({mode="ap-wds", encryption="wpa3"})
o:depends({mode="ap-wds", encryption="wpa3-mixed"})
o.rmempty = true
o.password = true

wpakey = s:taboption("encryption", Value, "_wpa_key", translate("Key"))
wpakey:depends("encryption", "psk")
wpakey:depends("encryption", "psk2")
wpakey:depends("encryption", "psk+psk2")
wpakey:depends("encryption", "psk-mixed")
wpakey:depends("encryption", "sae")
wpakey:depends("encryption", "sae-mixed")
wpakey.datatype = "wpakey"
wpakey.rmempty = true
wpakey.password = true

wpakey.cfgvalue = function(self, section, value)
	local key = m.uci:get("wireless", section, "key")
	if key == "1" or key == "2" or key == "3" or key == "4" then
		return nil
	end
	return key
end

wpakey.write = function(self, section, value)
	self.map.uci:set("wireless", section, "key", value)
	self.map.uci:delete("wireless", section, "key1")
end


wepslot = s:taboption("encryption", ListValue, "_wep_key", translate("Used Key Slot"))
wepslot:depends("encryption", "wep-open")
wepslot:depends("encryption", "wep-shared")
wepslot:value("1", translatef("Key #%d", 1))
wepslot:value("2", translatef("Key #%d", 2))
wepslot:value("3", translatef("Key #%d", 3))
wepslot:value("4", translatef("Key #%d", 4))

wepslot.cfgvalue = function(self, section)
	local slot = tonumber(m.uci:get("wireless", section, "key") or "")
	if not slot or slot < 1 or slot > 4 then
		return 1
	end
	return slot
end

wepslot.write = function(self, section, value)
	self.map.uci:set("wireless", section, "key", value)
end

local slot
for slot=1,4 do
	wepkey = s:taboption("encryption", Value, "key" .. slot, translatef("Key #%d", slot))
	wepkey:depends("encryption", "wep-open")
	wepkey:depends("encryption", "wep-shared")
	wepkey.datatype = "wepkey"
	wepkey.rmempty = true
	wepkey.password = true

	function wepkey.write(self, section, value)
		if value and (#value == 5 or #value == 13) then
			value = "s:" .. value
		end
		return Value.write(self, section, value)
	end
end


if hwtype == "mac80211" or hwtype == "prism2" then
	-- Probe 802.11r support (and EAP support as a proxy for Openwrt)
	local has_80211r = (os.execute("hostapd -v11r 2>/dev/null || hostapd -veap 2>/dev/null") == 0)
	o = s:taboption("roaming", Flag, "ieee80211r", translate("802.11r Fast Transition"), translate('Enables fast roaming among access points that belong to the same Mobility Domain'))
	o:depends({mode="ap", encryption="wpa2"})
	o:depends({mode="ap", encryption="wpa3"})
	o:depends({mode="ap", encryption="wpa3-mixed"})
	o:depends({mode="ap", encryption="wpa3-192"})
	o:depends({mode="ap-wds", encryption="wpa2"})
	o:depends({mode="ap-wds", encryption="wpa3"})
	o:depends({mode="ap-wds", encryption="wpa3-mixed"})
	o:depends({mode="ap-wds", encryption="wpa3-192"})
	if has_80211r then
		o:depends({mode="ap", encryption="psk2"})
		o:depends({mode="ap", encryption="psk-mixed"})
		o:depends({mode="ap", encryption="sae"})
		o:depends({mode="ap", encryption="sae-mixed"})
		o:depends({mode="ap-wds", encryption="psk2"})
		o:depends({mode="ap-wds", encryption="psk-mixed"})
		o:depends({mode="ap-wds", encryption="sae"})
		o:depends({mode="ap-wds", encryption="sae-mixed"})
	end
	o.rmempty = true

	o = s:taboption("roaming", Value, "nasid", translate("NAS ID"), translate('Used for two different purposes: RADIUS NAS ID and 802.11r R0KH-ID. Not needed with normal WPA(2)-PSK.'))
	o:depends({mode="ap", encryption="wpa"})
	o:depends({mode="ap", encryption="wpa2"})
	o:depends({mode="ap", encryption="wpa3"})
	o:depends({mode="ap", encryption="wpa3-mixed"})
	o:depends({mode="ap", encryption="wpa3-192"})
	o:depends({mode="ap-wds", encryption="wpa"})
	o:depends({mode="ap-wds", encryption="wpa2"})
	o:depends({mode="ap-wds", encryption="wpa3"})
	o:depends({mode="ap-wds", encryption="wpa3-mixed"})
	o:depends({mode="ap-wds", encryption="wpa3-192"})
	o:depends({ ieee80211r = "1" })
	o.rmempty = true

	o = s:taboption("roaming", Value, "mobility_domain", translate("Mobility Domain"), translate("4-character hexadecimal ID"))
	o:depends({ ieee80211r = "1" })
	o.placeholder = "4f57"
	o.datatype = "and(hexstring,rangelength(4,4))"
	o.rmempty = true

	o = s:taboption("roaming", Value, "reassociation_deadline", translate("Reassociation Deadline"), translate("time units (TUs / 1.024 ms) [1000-65535]"))
	o:depends({ ieee80211r = "1" })
	o.placeholder = "1000"
	o.datatype = "range(1000,65535)"
	o.rmempty = true

	o = s:taboption("roaming", ListValue, "ft_over_ds", translate("FT protocol"))
	o:depends({ ieee80211r = "1" })
	o:value("1", translatef("FT over DS"))
	o:value("0", translatef("FT over the Air"))
	o.rmempty = true

	o = s:taboption("roaming", Flag, "ft_psk_generate_local", translate("Generate PMK locally"), translate("When using a PSK, the PMK can be automatically generated. When enabled, the R0/R1 key options below are not applied. Disable this to use the R0 and R1 key options."))
	o:depends({ ieee80211r = "1", mode = "ap", encryption = "psk2" })
	o:depends({ ieee80211r = "1", mode = "ap", encryption = "psk-mixed" })
	o:depends({ ieee80211r = "1", mode = "ap-wds", encryption = "psk2" })
	o:depends({ ieee80211r = "1", mode = "ap-wds", encryption = "psk-mixed" })

	o = s:taboption("roaming", Value, "r0_key_lifetime", translate("R0 Key Lifetime"), translate("minutes"))
	o:depends({ ieee80211r = "1" })
	o.placeholder = "10000"
	o.datatype = "uinteger"
	o.rmempty = true

	o = s:taboption("roaming", Value, "r1_key_holder", translate("R1 Key Holder"), translate("6-octet identifier as a hex string - no colons"))
	o:depends({ ieee80211r = "1" })
	o.placeholder = "00004f577274"
	o.datatype = "and(hexstring,rangelength(12,12))"
	o.rmempty = true

	o = s:taboption("roaming", Flag, "pmk_r1_push", translate("PMK R1 Push"))
	o:depends({ ieee80211r = "1" })
	o.placeholder = "0"
	o.rmempty = true

	o = s:taboption("roaming", DynamicList, "r0kh", translate("External R0 Key Holder List"),
		translate('List of R0KHs in the same Mobility Domain. <br />Format: MAC-address,NAS-Identifier,256-bit key as hex string. <br />This list is used to map R0KH-ID (NAS Identifier) to a destination MAC address when requesting PMK-R1 key from the R0KH that the STA used during the Initial Mobility Domain Association.'))
	o:depends({ ieee80211r = "1" })
	o.rmempty = true

	o = s:taboption("roaming", DynamicList, "r1kh", translate("External R1 Key Holder List"),
		translate('List of R1KHs in the same Mobility Domain. <br />Format: MAC-address,R1KH-ID as 6 octets with colons,256-bit key as hex string. <br />This list is used to map R1KH-ID to a destination MAC address when sending PMK-R1 key from the R0KH. This is also the list of authorized R1KHs in the MD that can request PMK-R1 keys.'))
	o:depends({ ieee80211r = "1" })
	o.rmempty = true
	-- End of 802.11r options

	local has_eap  = (os.execute("hostapd -veap >/dev/null 2>/dev/null") == 0)
	-- Probe 802.11k and 802.11v support via EAP support (full hostapd has EAP)
	if has_eap then
		-- 802.11k settings start
		o = s:taboption("roaming", Flag, "ieee80211k", translate("802.11k RRM"), translate('Radio Resource Measurement - Sends beacons to assist roaming. Not all clients support this.'))
		o:depends('mode', 'ap')
		o:depends('mode', 'ap-wds')
		
		o = s:taboption("roaming", Flag, "rrm_neighbor_report", translate("Neighbour Report"), translate('802.11k: Enable neighbor report via radio measurements.'))
		o:depends({ ieee80211k = "1" })
		o.default = o.enabled

		o = s:taboption("roaming", Flag, "rrm_beacon_report", translate("Beacon Report"), translate('802.11k: Enable beacon report via radio measurements.'))
		o:depends({ ieee80211k = "1" })
		o.default = o.enabled
		-- 802.11k settings end

		-- 802.11v settings start
		o = s:taboption("roaming", ListValue, "time_advertisement", translate("Time advertisement"), translate('802.11v: Time Advertisement in management frames.'))
		o:depends({ieee80211v="1"})
		o:value("0", translate("Disabled"))
		o:value("2", translate("Enabled"))
		o.rmempty = true
		function o.write(self, section, value)
			if value == "2" then
				return Value.write(self, section, value)
			else
				return Value.remove(self, section)
			end
		end

		local tz = m.uci:get('system', '@system[0]', 'timezone')
		o = s:taboption("roaming", Value, "time_zone", translate("Time zone"), translate('802.11v: Local Time Zone Advertisement in management frames.'))
		o:value(tz)
		o.rmempty = true

		o = s:taboption("roaming", Flag, "wnm_sleep_mode", translate("WNM Sleep Mode"), translate('802.11v: Wireless Network Management (WNM) Sleep Mode (extended sleep mode for stations).'))
		o.rmempty = true

		-- wnm_sleep_mode_no_keys: https://git.openwrt.org/?p=openwrt/openwrt.git;a=commitdiff;h=bf98faaac8ed24cf7d3d93dd4fcd7304d109363b
		o = s:taboption("roaming", Flag, "wnm_sleep_mode_no_keys", translate("WNM Sleep Mode Fixes"), translate('802.11v: Wireless Network Management (WNM) Sleep Mode Fixes: Prevents reinstallation attacks.'))
		o.rmempty = true

		o = s:taboption("roaming", Flag, "bss_transition", translate("BSS Transition"), translate('802.11v: Basic Service Set (BSS) transition management.'))
		o.rmempty = true

		-- in master, but not 21.02.1: proxy_arp
		o = s:taboption("roaming", Flag, "proxy_arp", translate("ProxyARP"), translate('802.11v: Proxy ARP enables non-AP STA to remain in power-save for longer.'))
		o.rmempty = true
		-- TODO: na_mcast_to_ucast is missing: needs adding to hostapd.sh - nice to have
		-- 802.11v settings end
	end

	eaptype = s:taboption("encryption", ListValue, "eap_type", translate("EAP-Method"))
	eaptype:value("tls",  "TLS")
	eaptype:value("ttls", "TTLS")
	eaptype:value("peap", "PEAP")
	eaptype:value("fast", "FAST")
	eaptype:depends({mode="sta", encryption="wpa"})
	eaptype:depends({mode="sta", encryption="wpa2"})
	eaptype:depends({mode="sta-wds", encryption="wpa"})
	eaptype:depends({mode="sta-wds", encryption="wpa2"})

	cacert = s:taboption("encryption", FileUpload, "ca_cert", translate("Path to CA-Certificate"))
	cacert:depends({mode="sta", encryption="wpa"})
	cacert:depends({mode="sta", encryption="wpa2"})
	cacert:depends({mode="sta-wds", encryption="wpa"})
	cacert:depends({mode="sta-wds", encryption="wpa2"})
	cacert.rmempty = true

	clientcert = s:taboption("encryption", FileUpload, "client_cert", translate("Path to Client-Certificate"))
	clientcert:depends({mode="sta", eap_type="tls", encryption="wpa"})
	clientcert:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	clientcert:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})
	clientcert:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})

	privkey = s:taboption("encryption", FileUpload, "priv_key", translate("Path to Private Key"))
	privkey:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	privkey:depends({mode="sta", eap_type="tls", encryption="wpa"})
	privkey:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})
	privkey:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})

	privkeypwd = s:taboption("encryption", Value, "priv_key_pwd", translate("Password of Private Key"))
	privkeypwd:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	privkeypwd:depends({mode="sta", eap_type="tls", encryption="wpa"})
	privkeypwd:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})
	privkeypwd:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})
	privkeypwd.rmempty = true
	privkeypwd.password = true

	auth = s:taboption("encryption", ListValue, "auth", translate("Authentication"))
	auth:value("PAP", "PAP", {eap_type="ttls"})
	auth:value("CHAP", "CHAP", {eap_type="ttls"})
	auth:value("MSCHAP", "MSCHAP", {eap_type="ttls"})
	auth:value("MSCHAPV2", "MSCHAPv2", {eap_type="ttls"})
	auth:value("EAP-GTC")
	auth:value("EAP-MD5")
	auth:value("EAP-MSCHAPV2")
	auth:value("EAP-TLS")
	auth:depends({mode="sta", eap_type="fast", encryption="wpa2"})
	auth:depends({mode="sta", eap_type="fast", encryption="wpa"})
	auth:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	auth:depends({mode="sta", eap_type="peap", encryption="wpa"})
	auth:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	auth:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	auth:depends({mode="sta-wds", eap_type="fast", encryption="wpa2"})
	auth:depends({mode="sta-wds", eap_type="fast", encryption="wpa"})
	auth:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	auth:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	auth:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	auth:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})

	cacert2 = s:taboption("encryption", FileUpload, "ca_cert2", translate("Path to inner CA-Certificate"))
	cacert2:depends({mode="sta", auth="EAP-TLS", encryption="wpa"})
	cacert2:depends({mode="sta", auth="EAP-TLS", encryption="wpa2"})
	cacert2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa"})
	cacert2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa2"})

	clientcert2 = s:taboption("encryption", FileUpload, "client_cert2", translate("Path to inner Client-Certificate"))
	clientcert2:depends({mode="sta", auth="EAP-TLS", encryption="wpa"})
	clientcert2:depends({mode="sta", auth="EAP-TLS", encryption="wpa2"})
	clientcert2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa"})
	clientcert2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa2"})

	privkey2 = s:taboption("encryption", FileUpload, "priv_key2", translate("Path to inner Private Key"))
	privkey2:depends({mode="sta", auth="EAP-TLS", encryption="wpa"})
	privkey2:depends({mode="sta", auth="EAP-TLS", encryption="wpa2"})
	privkey2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa"})
	privkey2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa2"})

	privkeypwd2 = s:taboption("encryption", Value, "priv_key2_pwd", translate("Password of inner Private Key"))
	privkeypwd2:depends({mode="sta", auth="EAP-TLS", encryption="wpa"})
	privkeypwd2:depends({mode="sta", auth="EAP-TLS", encryption="wpa2"})
	privkeypwd2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa"})
	privkeypwd2:depends({mode="sta-wds", auth="EAP-TLS", encryption="wpa2"})
	privkeypwd2.rmempty = true
	privkeypwd2.password = true

	identity = s:taboption("encryption", Value, "identity", translate("Identity"))
	identity:depends({mode="sta", eap_type="fast", encryption="wpa2"})
	identity:depends({mode="sta", eap_type="fast", encryption="wpa"})
	identity:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	identity:depends({mode="sta", eap_type="peap", encryption="wpa"})
	identity:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	identity:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	identity:depends({mode="sta-wds", eap_type="fast", encryption="wpa2"})
	identity:depends({mode="sta-wds", eap_type="fast", encryption="wpa"})
	identity:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	identity:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	identity:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	identity:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})
	identity:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	identity:depends({mode="sta", eap_type="tls", encryption="wpa"})
	identity:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})
	identity:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})

	anonymous_identity = s:taboption("encryption", Value, "anonymous_identity", translate("Anonymous Identity"))
	anonymous_identity:depends({mode="sta", eap_type="fast", encryption="wpa2"})
	anonymous_identity:depends({mode="sta", eap_type="fast", encryption="wpa"})
	anonymous_identity:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	anonymous_identity:depends({mode="sta", eap_type="peap", encryption="wpa"})
	anonymous_identity:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	anonymous_identity:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	anonymous_identity:depends({mode="sta-wds", eap_type="fast", encryption="wpa2"})
	anonymous_identity:depends({mode="sta-wds", eap_type="fast", encryption="wpa"})
	anonymous_identity:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	anonymous_identity:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	anonymous_identity:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	anonymous_identity:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})
	anonymous_identity:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	anonymous_identity:depends({mode="sta", eap_type="tls", encryption="wpa"})
	anonymous_identity:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})
	anonymous_identity:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})

	password = s:taboption("encryption", Value, "password", translate("Password"))
	password:depends({mode="sta", eap_type="fast", encryption="wpa2"})
	password:depends({mode="sta", eap_type="fast", encryption="wpa"})
	password:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	password:depends({mode="sta", eap_type="peap", encryption="wpa"})
	password:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	password:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	password:depends({mode="sta-wds", eap_type="fast", encryption="wpa2"})
	password:depends({mode="sta-wds", eap_type="fast", encryption="wpa"})
	password:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	password:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	password:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	password:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})
	password.rmempty = true
	password.password = true
end

-- ieee802.11w options
if hwtype == "mac80211" then
	local has_80211w = (os.execute("hostapd -v11w 2>/dev/null || hostapd -veap 2>/dev/null") == 0)
	if has_80211w then
		ieee80211w = s:taboption("encryption", ListValue, "ieee80211w",
			translate("802.11w Management Frame Protection"),
			translate("Note: Some wireless drivers do not fully support 802.11w. E.g. mwlwifi may have problems"))
		ieee80211w.default = ""
		ieee80211w.rmempty = true
		ieee80211w:value("", translate("Disabled (default)"))
		ieee80211w:value("1", translate("Optional"))
		ieee80211w:value("2", translate("Required"))
		ieee80211w:depends({mode="ap", encryption="owe"})
		ieee80211w:depends({mode="ap", encryption="psk2"})
		ieee80211w:depends({mode="ap", encryption="psk-mixed"})
		ieee80211w:depends({mode="ap", encryption="sae"})
		ieee80211w:depends({mode="ap", encryption="sae-mixed"})
		ieee80211w:depends({mode="ap", encryption="wpa2"})
		ieee80211w:depends({mode="ap", encryption="wpa3"})
		ieee80211w:depends({mode="ap", encryption="wpa3-mixed"})
		ieee80211w:depends({mode="ap-wds", encryption="owe"})
		ieee80211w:depends({mode="ap-wds", encryption="psk2"})
		ieee80211w:depends({mode="ap-wds", encryption="psk-mixed"})
		ieee80211w:depends({mode="ap-wds", encryption="sae"})
		ieee80211w:depends({mode="ap-wds", encryption="sae-mixed"})
		ieee80211w:depends({mode="ap-wds", encryption="wpa2"})
		ieee80211w:depends({mode="ap-wds", encryption="wpa3"})
		ieee80211w:depends({mode="ap-wds", encryption="wpa3-mixed"})
		ieee80211w:depends({mode="sta", encryption="owe"})
		ieee80211w:depends({mode="sta", encryption="psk2"})
		ieee80211w:depends({mode="sta", encryption="psk-mixed"})
		ieee80211w:depends({mode="sta", encryption="sae"})
		ieee80211w:depends({mode="sta", encryption="sae-mixed"})
		ieee80211w:depends({mode="sta", encryption="wpa2"})
		ieee80211w:depends({mode="sta", encryption="wpa3"})
		ieee80211w:depends({mode="sta", encryption="wpa3-mixed"})
		ieee80211w:depends({mode="sta-wds", encryption="owe"})
		ieee80211w:depends({mode="sta-wds", encryption="psk2"})
		ieee80211w:depends({mode="sta-wds", encryption="psk-mixed"})
		ieee80211w:depends({mode="sta-wds", encryption="sae"})
		ieee80211w:depends({mode="sta-wds", encryption="sae-mixed"})
		ieee80211w:depends({mode="sta-wds", encryption="wpa2"})
		ieee80211w:depends({mode="sta-wds", encryption="wpa3"})
		ieee80211w:depends({mode="sta-wds", encryption="wpa3-mixed"})

		max_timeout = s:taboption("encryption", Value, "ieee80211w_max_timeout",
				translate("802.11w maximum timeout"),
				translate("802.11w Association SA Query maximum timeout"))
		max_timeout:depends({ieee80211w="1"})
		max_timeout:depends({ieee80211w="2"})
		max_timeout.datatype = "uinteger"
		max_timeout.placeholder = "1000"
		max_timeout.rmempty = true

		retry_timeout = s:taboption("encryption", Value, "ieee80211w_retry_timeout",
				translate("802.11w retry timeout"),
				translate("802.11w Association SA Query retry timeout"))
		retry_timeout:depends({ieee80211w="1"})
		retry_timeout:depends({ieee80211w="2"})
		retry_timeout.datatype = "uinteger"
		retry_timeout.placeholder = "201"
		retry_timeout.rmempty = true

		local has_hostapd_ocv = (os.execute("hostapd -vocv 2>/dev/null") == 0)
		local has_wpasupplicant_ocv = (os.execute("wpa_supplicant -vocv 2>/dev/null") == 0)
		if has_hostapd_ocv or has_wpasupplicant_ocv then
			o = s:taboption("encryption", ListValue, "ocv", translate("Operating Channel Validation"),
				translate("Note: Workaround mode allows a STA that claims OCV capability to connect even if the STA doesn't send OCI or negotiate PMF."))
			o:value("0", translate("Disabled"))
			o:value("1", translate("Enabled"))
			o:value("2", translate("Enabled (workaround mode)"))
			o.default = "0"
			o:depends({ieee80211w="1"})
			o:depends({ieee80211w="2"})
			o.validate = function(self, value)
				--TODO
			end
		end
	end

	o = s:taboption("encryption", Flag, "wpa_disable_eapol_key_retries",
		translate("Enable key reinstallation (KRACK) countermeasures"),
		translate("Complicates key reinstallation attacks on the client side by disabling retransmission of EAPOL-Key frames that are used to install keys. This workaround might cause interoperability issues and reduced robustness of key negotiation especially in environments with heavy traffic load."))
	o:depends({mode="ap", encryption="psk2"})
	o:depends({mode="ap", encryption="psk-mixed"})
	o:depends({mode="ap", encryption="sae"})
	o:depends({mode="ap", encryption="sae-mixed"})
	o:depends({mode="ap", encryption="wpa2"})
	o:depends({mode="ap", encryption="wpa3"})
	o:depends({mode="ap", encryption="wpa3-mixed"})
	o:depends({mode="ap-wds", encryption="psk2"})
	o:depends({mode="ap-wds", encryption="psk-mixed"})
	o:depends({mode="ap-wds", encryption="sae"})
	o:depends({mode="ap-wds", encryption="sae-mixed"})
	o:depends({mode="ap-wds", encryption="wpa2"})
	o:depends({mode="ap-wds", encryption="wpa3"})
	o:depends({mode="ap-wds", encryption="wpa3-mixed"})
end

if hwtype == "mac80211" or hwtype == "prism2" then
	local has_wps = (os.execute("hostapd -vwps >/dev/null 2>/dev/null") == 0)
	local wpasupplicant = fs.access("/usr/sbin/wpa_supplicant")
	if has_wps and wpasupplicant then
		o = s:taboption("encryption", Flag, "wps_pushbutton", translate('Enable WPS pushbutton, requires WPA(2)-PSK/WPA3-SAE'))
		o.enabled = "1"
		o.disabled = "0"
		o.default = o.disabled
		o:depends("encryption", "psk")
		o:depends("encryption", "psk2")
		o:depends("encryption", "psk-mixed")
		o:depends("encryption", "sae")
		o:depends("encryption", "sae-mixed")
	end
end

return m
