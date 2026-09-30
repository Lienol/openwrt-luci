local fs = require "nixio.fs"
local jsonc = require "luci.jsonc"
local util = require "luci.util"
local n = util.ubus("service", "list", { name = "natmap"}) or {}
local status = {}
if n.natmap and n.natmap.instances then
	for k, v in pairs(n.natmap.instances) do
		if v.running and v.pid then
			local f = "/var/run/natmap/" .. v.pid .. ".json"
			if fs.access(f) then
				local f_raw = fs.readfile(f)
				status[k] = jsonc.parse(f_raw)
			end
		end
	end
end

m = Map("natmap")
m.title = translate("NATMap")

s = m:section(TypedSection, "natmap", "")
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"
s.extedit = luci.dispatcher.build_url("admin", "services", "natmap", "config", "%s")
function s.create(self, t)
	local section = TypedSection.create(self, t)
	luci.http.redirect(self.extedit:format(section))
end

o = s:option(Flag, "enable", translate("Enable"))
o.width = "5%"
o.default = "1"
o.rmempty = false

o = s:option(DummyValue, "udp_mode", translate("Protocol"))
function o.cfgvalue(self, section)
	local val = Value.cfgvalue(self, section)
	if val == "0" then return translate("TCP") end
	if val == "1" then return translate("UDP") end
	return val
end

o = s:option(DummyValue, "port", translate("Port"))

o = s:option(DummyValue, "_external_ip", translate("External IP"))
function o.cfgvalue(self, section)
	return status[section] and status[section].ip or nil
end

o = s:option(DummyValue, "_external_port", translate("External Port"))
function o.cfgvalue(self, section)
	return status[section] and status[section].port or nil
end

return m
