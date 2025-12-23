-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local ipc = require "luci.ip"
local o
require "luci.util"
local sys = require "luci.sys"

m = Map("dhcp", translate("DHCP"))

s = m:section(TypedSection, "dnsmasq", "")
s.anonymous = true
s.addremove = false

s:tab("general", translate("General Settings"))
s:tab("devices", translate("Devices &amp; Ports"))
s:tab("logging", translate("Log"))
s:tab("files", translate("File"))
s:tab("tftp", translate("TFTP Settings"))

s:taboption("general", Flag, "authoritative",
	translate("Authoritative"),
	translate("This is the only <abbr title=\"Dynamic Host Configuration Protocol\">DHCP</" ..
		"abbr> in the local network"))

s:taboption("general", Value, "domain",
	translate("Local domain"),
	translate("Local domain suffix appended to DHCP names and hosts file entries"))

se = s:taboption("general", Flag, "sequential_ip",
	translate("Allocate IP sequentially"),
	translate("Allocate IP addresses sequentially, starting from the lowest available address"))
se.optional = true

lm = s:taboption("general", Value, "dhcpleasemax",
	translate("<abbr title=\"maximal\">Max.</abbr> <abbr title=\"Dynamic Host Configuration " ..
		"Protocol\">DHCP</abbr> leases"),
	translate("Maximum allowed number of active DHCP leases"))

lm.optional = true
lm.datatype = "uinteger"
lm.placeholder = translate("unlimited")


o = s:taboption("devices", Flag, "nonwildcard",
	translate("Non-wildcard"),
	translate("Bind only to specific interfaces rather than wildcard address."))
o.optional = false
o.rmempty = false

o = s:taboption("devices", DynamicList, "interface",
	translate("Listen Interfaces"),
	translate("Limit listening to these interfaces, and loopback."))
o.optional = true
o:depends("nonwildcard", true)

o = s:taboption("devices", DynamicList, "notinterface",
	translate("Exclude interfaces"),
	translate("Prevent listening on these interfaces."))
o.optional = true
o:depends("nonwildcard", true)


o = s:taboption("logging", Flag, "logdhcp",
	translate("Extra DHCP logging"),
	translate("Log all options sent to DHCP clients and the tags used to determine them."))
o.optional = true

o = s:taboption("logging", Value, "logfacility",
	translate("Log facility"),
	translate("Set log class/facility for syslog entries."))
o.optional = true
o:value('KERN')
o:value('USER')
o:value('MAIL')
o:value('DAEMON')
o:value('AUTH')
o:value('LPR')
o:value('NEWS')
o:value('UUCP')
o:value('CRON')
o:value('LOCAL0')
o:value('LOCAL1')
o:value('LOCAL2')
o:value('LOCAL3')
o:value('LOCAL4')
o:value('LOCAL5')
o:value('LOCAL6')
o:value('LOCAL7')
o:value('-', 'stderr')

qu = s:taboption("logging", Flag, "quietdhcp",
	translate("Suppress logging"),
	translate("Suppress logging of the routine operation of these protocols"))
qu.optional = true
qu:depends("logdhcp", false)


s:taboption("files", Flag, "readethers",
	translate("Use <code>/etc/ethers</code>"),
	translate("Read <code>/etc/ethers</code> to configure the <abbr title=\"Dynamic Host " ..
		"Configuration Protocol\">DHCP</abbr>-Server"))

s:taboption("files", Value, "leasefile",
	translate("Leasefile"),
	translate("file where given <abbr title=\"Dynamic Host Configuration Protocol\">DHCP</" ..
		"abbr>-leases will be stored"))


s:taboption("tftp", Flag, "enable_tftp",
	translate("Enable TFTP server")).optional = true

tr = s:taboption("tftp", Value, "tftp_root",
	translate("TFTP server root"),
	translate("Root directory for files served via TFTP"))

tr.optional = true
tr:depends("enable_tftp", "1")
tr.placeholder = "/"

db = s:taboption("tftp", Value, "dhcp_boot",
	translate("Network boot image"),
	translate("Filename of the boot image advertised to clients"))

db.optional = true
db:depends("enable_tftp", "1")
db.placeholder = "pxelinux.0"


tag_s = m:section(TypedSection, "tag", translate("Tag"))
tag_s.template = "cbi/tblsection"
tag_s.anonymous = false
tag_s.addremove = true
tag_s.sortable = true
tag_s.extedit = "dhcp_tag_config/%s"
function tag_s.create(e, t)
	TypedSection.create(e, t)
	luci.http.redirect(e.extedit:format(t))
end
function tag_s.remove(e, t)
	m.uci:foreach("dhcp", "host", function(s)
		local tags = s.tag or {}
		if #tags > 0 then
			for i = #tags, 1, -1 do
				if t == tags[i] then
					sys.call('uci -q del_list dhcp.' .. s[".name"] .. '.tag="' .. t .. '"')
				end
			end
		end
	end)
	TypedSection.remove(e, t)
end

o = tag_s:option(DynamicList, "dhcp_option", translate("DHCP-Options"))

o = tag_s:option(Flag, "force", translate("Force") .. " " .. translate("DHCP-Options"))
o.default = 0
o.rmempty  = false


s = m:section(TypedSection, "host", translate("Static Leases"),
	translate("Static leases are used to assign fixed IP addresses and symbolic hostnames to " ..
		"DHCP clients. They are also required for non-dynamic interface configurations where " ..
		"only hosts with a corresponding lease are served.") .. "<br />" ..
	translate("Use the <em>Add</em> Button to add a new lease entry. The <em>MAC-Address</em> " ..
		"identifies the host, the <em>IPv4-Address</em> specifies the fixed address to " ..
		"use, and the <em>Hostname</em> is assigned as a symbolic name to the requesting host. " ..
		"The optional <em>Lease time</em> can be used to set non-standard host-specific " ..
		"lease time, e.g. 12h, 3d or infinite."))

s.addremove = true
s.anonymous = true
s.template = "cbi/tblsection"
s.extedit = "dhcp_static_leases_config/%s"

name = s:option(Value, "name", translate("Hostname"))
name.datatype = "hostname"
name.rmempty  = true

mac = s:option(Value, "mac", translate("<abbr title=\"Media Access Control\">MAC</abbr>-Address"))
mac.datatype = "list(macaddr)"
mac.rmempty  = true

ip = s:option(Value, "ip", translate("<abbr title=\"Internet Protocol Version 4\">IPv4</abbr>-Address"))
ip.datatype = "or(ip4addr,'ignore')"

--time = s:option(Value, "leasetime", translate("Lease time"))
--time.rmempty = true

tag = s:option(DynamicList, 'tag', translate('Tag'))
m.uci:foreach("dhcp", "tag", function(s)
	tag:value(s[".name"])
end)

duid = s:option(Value, "duid", translate("DUID"))
duid.datatype = "and(rangelength(20,36),hexstring)"

hostid = s:option(Value, "hostid", translate("<abbr title=\"Internet Protocol Version 6\">IPv6</abbr>-Suffix (hex)"))

ipc.neighbors({ family = 4 }, function(n)
	if n.mac and n.dest then
		ip:value(n.dest:string())
		mac:value(n.mac, "%s (%s)" %{ n.mac, n.dest:string() })
	end
end)

function ip.validate(self, value, section)
	local m = mac:formvalue(section) or ""
	local n = name:formvalue(section) or ""
	if value and #n == 0 and #m == 0 then
		return nil, translate("One of hostname or mac address must be specified!")
	end
	return Value.validate(self, value, section)
end

m:section(SimpleSection).template = "admin_network/lease_status"

return m