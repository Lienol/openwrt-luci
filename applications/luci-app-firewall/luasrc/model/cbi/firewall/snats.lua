local ds = require "luci.dispatcher"
local ft = require "luci.tools.firewall"

m = Map("firewall", translate("Firewall - NAT Rules"),
	translate("NAT rules allow fine grained control over the source IP to use for outbound or forwarded traffic."))

s = m:section(TypedSection, "nat", translate("NAT Rules"))
s.addremove = true
s.anonymous = true
s.sortable  = true
s.clonebtn = true
s.template = "cbi/tblsection"
s.extedit   = ds.build_url("admin/network/firewall/snats/%s")

function s.create(self, section)
	local id = TypedSection.create(self, section)
	if id then
		luci.http.redirect(string.format(self.extedit, id))
	end
end

local o = ft.opt_name(s, DummyValue, translate("Name"))
o.width = "25%"

local function rule_proto_txt(self, s)
	local f = self.map:get(s, "family")
	local p = ft.fmt_proto(self.map:get(s, "proto"),
	                       self.map:get(s, "icmp_type")) or translate("traffic")

	if f and f:match("4") then
		return "%s-%s" %{ translate("IPv4"), p }
	elseif f and f:match("6") then
		return "%s-%s" %{ translate("IPv6"), p }
	else
		return "%s %s" %{ translate("Any"), p }
	end
end

local function rule_src_txt(self, s)
	local z = ft.fmt_zone(self.map:get(s, "src"), translate("any zone"))
	local a = ft.fmt_ip(self.map:get(s, "src_ip"), translate("any host"))
	local p = ft.fmt_port(self.map:get(s, "src_port"))
	local m = ft.fmt_mac(self.map:get(s, "src_mac"))

	if p and m then
		return translatef("From %s in %s with source %s and %s", a, z, p, m)
	elseif p or m then
		return translatef("From %s in %s with source %s", a, z, p or m)
	else
		return translatef("From %s in %s", a, z)
	end
end

local function snat_dest_txt(self, s)
	local z = ft.fmt_zone(self.map:get(s, "dest"), translate("any zone"))
	local a = ft.fmt_ip(self.map:get(s, "dest_ip"), translate("any host"))
	local p = ft.fmt_port(self.map:get(s, "dest_port")) or
		ft.fmt_port(self.map:get(s, "src_dport"))

	if p then
		return translatef("To %s, %s in %s", a, p, z)
	else
		return translatef("To %s in %s", a, z)
	end
end

local function rule_target_txt(self, s)
	local t = self.map:get(s, "target")
	if t == "SNAT" then
		local snat_ip = self.map:get(s, "snat_ip") or ""
		local snat_port = self.map:get(s, "snat_port") or ""
		return translatef('<var data-tooltip="SNAT">Statically rewrite</var> to source IP <var>%s</var> port <var>%s</var>', snat_ip, snat_port)
	elseif t == "MASQUERADE" then
		return translatef('<var data-tooltip="MASQUERADE">Automatically rewrite</var> source IP')
	elseif t == "ACCEPT" then
		return translatef('<var data-tooltip="ACCEPT">Prevent source rewrite</var>')
	end
	return t
end

match = s:option(DummyValue, "_match", translate("Match"))
match.rawhtml = true
match.width   = "25%"
function match.cfgvalue(self, s)
	return "<small>%s<br />%s<br />%s</small>" % {
		rule_proto_txt(self, s),
		rule_src_txt(self, s),
		snat_dest_txt(self, s)
	}
end

snat = s:option(DummyValue, "_target", translate("Action"))
snat.rawhtml = true
snat.width   = "25%"
function snat.cfgvalue(self, s)
	return rule_target_txt(self, s)
end

ft.opt_enabled(s, Flag, translate("Enable")).width = "5%"


return m
