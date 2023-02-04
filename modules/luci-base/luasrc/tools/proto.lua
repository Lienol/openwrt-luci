-- Copyright 2012 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.tools.proto", package.seeall)

local uci = require("luci.model.uci").cursor()

function opt_macaddr(s, ifc, ...)
	local v = luci.cbi.Value
	local o = s:taboption("advanced", v, "macaddr", ...)

	o.placeholder = ifc and ifc:mac()
	o.datatype    = "macaddr"

	if not o.placeholder or o.placeholder == "" then
		local uci_section = uci:get_all("network", s.section)
		if uci_section and uci_section.ifname then
			uci:foreach("network", "interface", function(e)
				if e.ifname == uci_section.ifname and e.macaddr then
					o.placeholder = e.macaddr
				end
			end)
		end
	end

	function o.cfgvalue(self, section)
		local w = ifc and ifc:get_wifinet()
		if w then
			return w:get("macaddr")
		else
			return v.cfgvalue(self, section)
		end
	end

	function o.write(self, section, value)
		local w = ifc and ifc:get_wifinet()
		if w then
			w:set("macaddr", value)
		elseif value then
			local uci_section = uci:get_all("network", s.section)
			if uci_section and uci_section.ifname then
				uci:foreach("network", "interface", function(e)
					if s.section ~= e[".name"] and e.ifname == uci_section.ifname then
						o.map:set(e[".name"], "macaddr", value)
					end
				end)
				uci:foreach("network", "device", function(e)
					if e.name == uci_section.ifname then
						o.map:set(e[".name"], "macaddr", value)
					end
				end)
			end
			v.write(self, section, value)
		else
			v.remove(self, section)
		end
	end

	function o.remove(self, section)
		local uci_section = uci:get_all("network", s.section)
		if uci_section and uci_section.ifname then
			uci:foreach("network", "interface", function(e)
				if s.section ~= e[".name"] and e.ifname == uci_section.ifname then
					o.map:del(e[".name"], "macaddr")
				end
			end)
			uci:foreach("network", "device", function(e)
				if e.name == uci_section.ifname then
					o.map:del(e[".name"], "macaddr")
				end
			end)
		end
		self:write(section, nil)
	end
end
