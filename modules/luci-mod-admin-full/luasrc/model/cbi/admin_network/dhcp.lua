-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local ipc = require "luci.ip"
local o
require "luci.util"

m = Map("dhcp", translate("DHCP and DNS"),
	translate("Dnsmasq is a combined <abbr title=\"Dynamic Host Configuration Protocol" ..
		"\">DHCP</abbr>-Server and <abbr title=\"Domain Name System\">DNS</abbr>-" ..
		"Forwarder for <abbr title=\"Network Address Translation\">NAT</abbr> " ..
		"firewalls"))

s = m:section(TypedSection, "dnsmasq", translate("Server Settings"))
s.anonymous = true
s.addremove = false

s:tab("general", translate("General Settings"))
s:tab("devices", translate("Devices &amp; Ports"))
s:tab("dnssecopt", translate("DNSSEC"))
s:tab("filteropts", translate("Filter"))
s:tab("forward", translate("Forwards"))
s:tab("limits", translate("Limits"))
s:tab("logging", translate("Log"))
s:tab("files", translate("Resolv and Hosts Files"))
s:tab("tftp", translate("TFTP Settings"))

s:taboption("general", Flag, "dns_redirect", translate("DNS Redirect"), translate("Redirect client DNS to dnsmasq"))

s:taboption("general", Flag, "authoritative",
	translate("Authoritative"),
	translate("This is the only <abbr title=\"Dynamic Host Configuration Protocol\">DHCP</" ..
		"abbr> in the local network"))

s:taboption("general", Value, "local",
	translate("Local server"),
	translate("Local domain specification. Names matching this domain are never forwarded and are resolved from DHCP or hosts files only"))

s:taboption("general", Value, "domain",
	translate("Local domain"),
	translate("Local domain suffix appended to DHCP names and hosts file entries"))

s:taboption("general", Flag, "expandhosts",
	translate("Expand hosts"),
	translate("Add local domain suffix to names served from hosts files"))

addr = s:taboption("general", DynamicList, "address", translate("Addresses"),
	translate('Resolve specified FQDNs to an IP.'))
addr.optional = true
addr.placeholder = "/router.local/router.lan/192.168.0.1"

ipset = s:taboption("general", DynamicList, "ipset", translate("IP Sets"),
	translate('List of IP sets to populate with the IPs of DNS lookup results of the FQDNs also specified here.'))
ipset.optional = true
ipset.placeholder = "/example.org/ipset,ipset6"

se = s:taboption("general", Flag, "sequential_ip",
	translate("Allocate IP sequentially"),
	translate("Allocate IP addresses sequentially, starting from the lowest available address"))
se.optional = true

s:taboption("general", Flag, "allservers",
	translate("Use all servers"),
	translate("Setting this flag forces dnsmasq to send all queries to all available servers. The reply from the server which answers first will be returned to the original requester."))


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

pt = s:taboption("devices", Value, "port",
	translate("<abbr title=\"Domain Name System\">DNS</abbr> server port"),
	translate("Listening port for inbound DNS queries"))
pt.optional = true
pt.datatype = "port"
pt.placeholder = 53

qp = s:taboption("devices", Value, "queryport",
	translate("<abbr title=\"Domain Name System\">DNS</abbr> query port"),
	translate("Fixed source port for outbound DNS queries"))
qp.optional = true
qp.datatype = "port"
qp.placeholder = translate("any")

o = s:taboption("devices", Value, "minport",
	translate("Minimum source port #"),
	translatef('Min valid value %s.', '<code>1024</code>') .. ' ' .. translate("Useful for systems behind firewalls."))
o.optional = true
o.datatype = "port"
o.placeholder = 1024
o:depends("queryport", "")

o = s:taboption("devices", Value, "maxport",
	translate("Maximum source port #"),
	translatef('Max valid value %s.', '<code>65535</code>') .. ' ' .. translate("Useful for systems behind firewalls."))
o.optional = true
o.datatype = "port"
o.placeholder = 50000
o:depends("queryport", "")


local have_dnssec_support = luci.util.checklib("/usr/sbin/dnsmasq", "libhogweed.so")
if have_dnssec_support then
	o = s:taboption("dnssecopt", Flag, "dnssec",
		translate("DNSSEC"))
	o.optional = true

	o = s:taboption("dnssecopt", Flag, "dnsseccheckunsigned",
		translate("DNSSEC check unsigned"),
		translate("Requires upstream supports DNSSEC; verify unsigned domain responses really come from unsigned domains"))
	o.optional = true
end


o = s:taboption("filteropts", Flag, "domainneeded",
		translate("Domain required"),
		translate("Don't forward <abbr title=\"Domain Name System\">DNS</abbr>-Requests without " ..
		"<abbr title=\"Domain Name System\">DNS</abbr>-Name"))

rp = s:taboption("filteropts", Flag, "rebind_protection",
		translate("Rebind protection"),
		translate("Discard upstream RFC1918 responses"))
rp.rmempty = false

rl = s:taboption("filteropts", Flag, "rebind_localhost",
		translate("Allow localhost"),
		translate("Allow upstream responses in the 127.0.0.0/8 range, e.g. for RBL services"))
rl:depends("rebind_protection", "1")

rd = s:taboption("filteropts", DynamicList, "rebind_domain",
		translate("Domain whitelist"),
		translate("List of domains to allow RFC1918 responses for"))
rd.optional = true
rd:depends("rebind_protection", "1")
rd.datatype = "host(1)"
rd.placeholder = "ihost.netflix.com"

o = s:taboption("filteropts", Flag, "localservice",
		translate("Local Service Only"),
		translate("Limit DNS service to subnets interfaces on which we are serving DNS."))
o.optional = false
o.rmempty = false

bp = s:taboption("filteropts", Flag, "boguspriv",
		translate("Filter private"),
		translate("Do not forward reverse lookups for local networks"))
bp.default = bp.enabled

f2k = s:taboption("filteropts", Flag, "filterwin2k",
		translate("Filter SRV/SOA service discovery"),
		translate("Filters SRV/SOA service discovery, to avoid triggering dial-on-demand links.") .. '<br />' ..
		translate("May prevent VoIP or other services from working."))

filter_aaaa = s:taboption("filteropts", Flag, "filter_aaaa", translate("Filter IPv6 AAAA records"), translate("Remove IPv6 addresses from the results and only return IPv4 addresses."))
filter_aaaa.optional = true

filter_a = s:taboption("filteropts", Flag, "filter_a", translate("Filter IPv4 A records"), translate("Remove IPv4 addresses from the results and only return IPv6 addresses."))
filter_a.optional = true

https = s:taboption("filteropts", Flag, "filter_https", translate("Disable HTTPS DNS Type forwards"), translate("Filter HTTPS DNS Query Type Name Resolve"))
https.optional = true

unknown = s:taboption("filteropts", Flag, "filter_unknown", translate("Disable Unknown DNS Type forwards"), translate("Filter Unknown DNS Query Type Name Resolve"))
unknown.optional = true

lq = s:taboption("filteropts", Flag, "localise_queries",
		translate("Localise queries"),
		translate("Localise hostname depending on the requesting subnet if multiple IPs are available"))

o = s:taboption("filteropts", Flag, "nonegcache",
		translate("No negative cache"),
		translate("Do not cache negative replies, e.g. for not existing domains"))

bn = s:taboption("filteropts", DynamicList, "bogusnxdomain", translate("Bogus NX Domain Override"),
		translate("List of hosts that supply bogus NX domain results"))
bn.optional = true
bn.placeholder = "67.215.65.132"


df = s:taboption("forward", DynamicList, "server", translate("DNS forwardings"),
	translate("List of <abbr title=\"Domain Name System\">DNS</abbr> " ..
			"servers to forward requests to"))
df.optional = true
df.placeholder = "/example.org/10.1.2.3"

s:taboption("forward", Value, "serversfile",
	translate("Additional servers file"),
	translate("This file may contain lines like 'server=/domain/1.2.3.4' or 'server=1.2.3.4' for"..
	        "domain-specific or full upstream <abbr title=\"Domain Name System\">DNS</abbr> servers."))


lm = s:taboption("limits", Value, "dhcpleasemax",
	translate("<abbr title=\"maximal\">Max.</abbr> <abbr title=\"Dynamic Host Configuration " ..
		"Protocol\">DHCP</abbr> leases"),
	translate("Maximum allowed number of active DHCP leases"))

lm.optional = true
lm.datatype = "uinteger"
lm.placeholder = translate("unlimited")

em = s:taboption("limits", Value, "ednspacket_max",
	translate("<abbr title=\"maximal\">Max.</abbr> <abbr title=\"Extension Mechanisms for " ..
		"Domain Name System\">EDNS0</abbr> packet size"),
	translate("Maximum allowed size of EDNS.0 UDP packets"))

em.optional = true
em.datatype = "uinteger"
em.placeholder = 1280

cq = s:taboption("limits", Value, "dnsforwardmax",
	translate("<abbr title=\"maximal\">Max.</abbr> concurrent queries"),
	translate("Maximum allowed number of concurrent DNS queries"))
cq.optional = true
cq.datatype = "uinteger"
cq.placeholder = 150

cs = s:taboption("limits", Value, "cachesize",
	translate("Size of DNS query cache"),
	translate("Number of cached DNS entries (max is 10000, 0 is no caching)"))
cs.optional = true
cs.datatype = "range(0,10000)"
cs.placeholder = 1000

o = s:taboption("limits", Value, "min_cache_ttl",
	translate("Min cache TTL"),
	translate("Extend short TTL values to the seconds value given when caching them. Use with caution.") ..
	translate(" (Max 1h == 3600)"))
o.optional = true
o.datatype = "range(0,86400)"
o.placeholder = 60

o = s:taboption("limits", Value, "max_cache_ttl",
	translate("Max cache TTL"),
	translate("Set a maximum seconds TTL value for entries in the cache."))
o.optional = true
o.placeholder = 3600


s:taboption("logging", Flag, "logqueries",
	translate("Log queries"),
	translate("Write received DNS requests to syslog")).optional = true

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
o:value('-', _('stderr'))

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

s:taboption("files", Flag, "noresolv",
	translate("Ignore resolve file")).optional = true

rf = s:taboption("files", Value, "resolvfile",
	translate("Resolve file"),
	translate("local <abbr title=\"Domain Name System\">DNS</abbr> file"))

rf:depends("noresolv", "")
rf.optional = true

s:taboption("files", Flag, "strictorder",
	translate("Strict order"),
	translate("<abbr title=\"Domain Name System\">DNS</abbr> servers will be queried in the " ..
		"order of the resolvfile")).optional = true

s:taboption("files", Flag, "nohosts",
	translate("Ignore <code>/etc/hosts</code>")).optional = true

s:taboption("files", DynamicList, "addnhosts",
	translate("Additional Hosts files")).optional = true


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
s.extedit = "dhcp_config/%s"

name = s:option(Value, "name", translate("Hostname"))
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

time = s:option(Value, "leasetime", translate("Lease time"))
time.rmempty = true

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


d = m:section(TypedSection, "domain", translate("Hostnames"),
	translate('Hostnames are used to bind a domain name to an IP address. This setting is redundant for hostnames already configured with static leases, but it can be useful to rebind an FQDN.'))
d.addremove = true
d.anonymous = true
d.sortable = true
d.template = "cbi/tblsection"

o = d:option(Value, "name", translate("Hostname"))
o.datatype = "hostname"
o.rmempty  = true

o = d:option(Value, "ip", translate("IP address"))
o.datatype = "ipaddr"

o = d:option(Value, "comments", translate("Comments"))
o.rmempty  = true


mx = m:section(TypedSection, "mxhost", translate("MX"),
	translate('Bind service records to a domain name: specify the location of services.') ..
	'<br />' .. translate('You may add multiple records for the same domain.'))
mx.addremove = true
mx.anonymous = true
mx.sortable = true
mx.template = "cbi/tblsection"

o = mx:option(Value, "domain", translate("Domain"))
o.rmempty  = false
o.datatype = "hostname"
o.placeholder = "example.com."

o = mx:option(Value, "relay", translate("Relay"))
o.rmempty  = false
o.datatype = "hostname"
o.placeholder = "relay.example.com."

o = mx:option(Value, "pref", translate("Priority"))
o.rmempty  = true
o.datatype = "range(0,65535)"
o.placeholder = "0"

return m