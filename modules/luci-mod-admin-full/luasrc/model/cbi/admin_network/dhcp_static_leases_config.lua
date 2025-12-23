-- Copyright 2024 Lienol <lawlienol@gmail.com>

local ipc = require "luci.ip"
local uci = require "luci.model.uci".cursor()

m = Map("dhcp")

s = m:section(NamedSection, arg[1], translate("Static Leases"), translate("Edit static lease"))
s.addremove = false
s.dynamic = false

name = s:option(Value, "name", translate("Hostname"), translate('Optional hostname to assign'))
name.datatype = "hostname"
name.rmempty  = true

function name.write(self, section, value)
	Value.write(self, section, value)
	m:set(section, "dns", "1")
end

function name.remove(self, section)
	Value.remove(self, section)
	m:del(section, "dns")
end

mac = s:option(Value, "mac", translate("<abbr title=\"Media Access Control\">MAC</abbr>-Address"))
mac.datatype = "list(macaddr)"
mac.rmempty  = true

ip = s:option(Value, "ip", translate("<abbr title=\"Internet Protocol Version 4\">IPv4</abbr>-Address"))
ip.datatype = "or(ip4addr,'ignore')"

time = s:option(Value, "leasetime", translate("Lease time"), translate('Host-specific lease time, e.g. <code>5m</code>, <code>3h</code>, <code>7d</code>.'))
time.rmempty = true

duid = s:option(Value, "duid", translate("DUID"), translate('The DHCPv6-DUID (DHCP unique identifier) of this host.'))
duid.datatype = "and(rangelength(20,36),hexstring)"

hostid = s:option(Value, "hostid", translate("<abbr title=\"Internet Protocol Version 6\">IPv6</abbr>-Suffix (hex)"), translate('The IPv6 interface identifier (address suffix) as hexadecimal number (max. 16 chars).'))

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

tag = s:option(DynamicList, 'tag', translate('Tag'), translate('Assign new, freeform tags to this entry.'))
m.uci:foreach("dhcp", "tag", function(s)
	tag:value(s[".name"])
end)

match_tag = s:option(DynamicList, 'match_tag', translate('Match Tag'),
		translatef('When a host matches an entry then the special tag %s is set. Use %s to match all known hosts.', '<code>known</code>', '<code>known</code>') .. '<br /><br />' ..
		translatef('Ignore requests from unknown machines using %s.', '<code>!known</code>') .. '<br /><br />' ..
		translatef('If a host matches an entry which cannot be used because it specifies an address on a different subnet, the tag %s is set.', '<code>known-othernet</code>'))
match_tag:value('known', translate('known'))
match_tag:value('!known', translate('!known (not known)'))
match_tag:value('known-othernet', translate('known-othernet (on different subnet)'))
match_tag.optional = true

instance = s:option(Value, 'instance', translate('Instance'), translate('Dnsmasq instance to which this DHCP host section is bound. If unspecified, the section is valid for all dnsmasq instances.'))
instance.optional = true

broadcast = s:option(Flag, 'broadcast', translate('Broadcast'), translate('Force broadcast DHCP response.'))

dns = s:option(Flag, 'dns', translate('Forward/reverse DNS'), translate('Add static forward and reverse DNS entries for this host.'))

return m
