-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local o
require "luci.util"

local recordtypes = {
	'ANY',
	'A',
	'AAAA',
	'ALIAS',
	'CAA',
	'CERT',
	'CNAME',
	'DS',
	'HINFO',
	'HIP',
	'HTTPS',
	'KEY',
	'LOC',
	'MX',
	'NAPTR',
	'NS',
	'OPENPGPKEY',
	'PTR',
	'RP',
	'SIG',
	'SOA',
	'SRV',
	'SSHFP',
	'SVCB',
	'TLSA',
	'TXT',
	'URI',
}

m = Map("dhcp", translate("DNS"))

s = m:section(TypedSection, "dnsmasq", "")
s.anonymous = true
s.addremove = false

s:tab("general", translate("General Settings"))
s:tab("cache", translate("Cache"))
s:tab("devices", translate("Devices &amp; Ports"))
s:tab("dnssecopt", translate("DNSSEC"))
s:tab("filteropts", translate("Filter"))
s:tab("forward", translate("Forwards"))
s:tab("limits", translate("Limits"))
s:tab("logging", translate("Log"))
s:tab("files", translate("Resolv and Hosts Files"))

s:taboption("general", Flag, "dns_redirect", translate("DNS Redirect"), translate("Redirect client DNS to dnsmasq"))

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

s:taboption("general", Flag, "allservers",
	translate("Use all servers"),
	translate("Setting this flag forces dnsmasq to send all queries to all available servers. The reply from the server which answers first will be returned to the original requester."))


o = s:taboption('cache', DynamicList, 'cache_rr', translate('Cache arbitrary RR'),
	translate('By default, dnsmasq caches A, AAAA, CNAME and SRV DNS record types.') .. '<br/>' ..
	translate('This option adds additional record types to the cache.'))
o.optional = true
for _, v in ipairs(recordtypes) do
	o:value(v)
end


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

o = s:taboption('filteropts', DynamicList, 'filter_rr', translate('Filter arbitrary RR'), translate('Removes records of the specified type(s) from answers.'))
o.optional = true
for _, v in ipairs(recordtypes) do
	o:value(v)
end

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

o = s:taboption("forward", Value, "serversfile",
		translate("Additional servers file"),
		translate("This file may contain lines like 'server=/domain/1.2.3.4' or 'server=1.2.3.4' for"..
			"domain-specific or full upstream <abbr title=\"Domain Name System\">DNS</abbr> servers."))
o.placeholder = "/etc/dnsmasq.servers"

o = s:taboption('forward', Value, 'addmac',
	translate('Add requestor MAC'),
	translate('Add the MAC address of the requestor to DNS queries which are forwarded upstream.') .. ' ' .. '<br />' ..
	translatef('%s uses the default MAC address format encoding', '<code>enabled</code>') .. ' ' .. '<br />' ..
	translatef('%s uses an alternative encoding of the MAC as base64', '<code>base64</code>') .. ' ' .. '<br />' ..
	translatef('%s uses a human-readable encoding of hex-and-colons', '<code>text</code>'))
o.optional = true
o:value('', translate('off'))
o:value('1', translate('enabled (default)'))
o:value('base64')
o:value('text')

s:taboption('forward', Flag, 'stripmac',
	translate('Remove MAC address before forwarding query'),
	translate('Remove any MAC address information already in downstream queries before forwarding upstream.'))

o = s:taboption('forward', Value, 'addsubnet',
	translate('Add subnet address to forwards'),
	translate('Add a subnet address to the DNS queries which are forwarded upstream, leaving this value empty disables the feature.') .. ' ' ..
	translate('If an address is specified in the flag, it will be used, otherwise, the address of the requestor will be used.') .. ' ' ..
	translate('The amount of the address forwarded depends on the prefix length parameter: 32 (128 for IPv6) forwards the whole address, zero forwards none of it but still marks the request so that no upstream nameserver will add client address information either.') .. ' ' .. '<br />' ..
	translatef('The default (%s) is zero for both IPv4 and IPv6.', '<code>0,0</code>') .. ' ' .. '<br />' ..
	translatef('%s adds the /24 and /96 subnets of the requestor for IPv4 and IPv6 requestors, respectively.', '<code>24,96</code>') .. ' ' .. '<br />' ..
	translatef('%s adds 1.2.3.0/24 for IPv4 requestors and ::/0 for IPv6 requestors.', '<code>1.2.3.4/24</code>') .. ' ' .. '<br />' ..
	translatef('%s adds 1.2.3.0/24 for both IPv4 and IPv6 requestors.', '<code>1.2.3.4/24,1.2.3.4/24</code>'))
o.optional = true;

s:taboption('forward', Flag, 'stripsubnet',
	translate('Remove subnet address before forwarding query'),
	translate('Remove any subnet address already present in a downstream query before forwarding it upstream.'))


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

o = s:taboption('files', Flag, 'ignore_hosts_dir',
	translate('Ignore hosts files directory'),
	translate('On: use instance specific hosts file only') .. '<br/>' ..
	translate('Off: use all files in the directory including the instance specific hosts file'))
o.optional = true

s:taboption("files", Flag, "nohosts",
	translate("Ignore <code>/etc/hosts</code>")).optional = true

s:taboption("files", DynamicList, "addnhosts",
	translate("Additional Hosts files")).optional = true


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


cname = m:section(TypedSection, "cname", translate("CNAME"), translate('Set an alias for a hostname.'))
cname.addremove = true
cname.anonymous = true
cname.sortable = true
cname.template = "cbi/tblsection"

o = cname:option(Value, "cname", translate("Domain"))
o.rmempty  = false
o.placeholder = "www.example.com."

o = cname:option(Value, "target", translate("Target"))
o.rmempty  = false
o.datatype = "hostname"
o.placeholder = "example.com."


srv = m:section(TypedSection, "srvhost", translate("SRV"),
		translatef('Bind service records to a domain name: specify the location of services. See <a href="%s">RFC2782</a>.', 'https://datatracker.ietf.org/doc/html/rfc2782')
		.. "<br />" .. translate('_service: _sip, _ldap, _imap, _stun, _xmpp-client, … . (Note: while _http is possible, no browsers support SRV records.)')
		.. "<br />" .. translate('_proto: _tcp, _udp, _sctp, _quic, … .')
		.. "<br />" .. translate('You may add multiple records for the same Target.')
		.. "<br />" .. translate('Larger weights (of the same prio) are given a proportionately higher probability of being selected.'))
srv.addremove = true
srv.anonymous = true
srv.sortable = true
srv.template = "cbi/tblsection"

o = srv:option(Value, "srv", translate("SRV"), translate('Syntax:') .. ' ' .. '<code>_service._proto.example.com.</code>')
o.rmempty  = false
o.datatype = "hostname"
o.placeholder = "_sip._tcp.example.com."

o = srv:option(Value, "target", translate("Target"), translate('CNAME or fqdn'))
o.rmempty  = false
o.datatype = "hostname"
o.placeholder = "sip.example.com."

o = srv:option(Value, "port", translate("Port"))
o.rmempty  = false
o.datatype = "port"
o.placeholder = "5060"

o = srv:option(Value, "class", translate("Priority"), translate('Ordinal: lower comes first.'))
o.rmempty  = true
o.datatype = "range(0,65535)"
o.placeholder = "10"

o = srv:option(Value, "weight", translate("Weight"))
o.rmempty  = true
o.datatype = "range(0,65535)"
o.placeholder = "50"


dnsrr = m:section(TypedSection, "dnsrr", translate("DNS-RR"),
		translate('Set an arbitrary resource record (RR) type.') .. "<br />" ..
		translate('Hexdata is automatically en/decoded on save and load'))
dnsrr.addremove = true
dnsrr.anonymous = true
dnsrr.sortable = true
dnsrr.template = "cbi/tblsection"

o = dnsrr:option(Value, "rrname", translate("Resource Record Name"))
o.rmempty  = false
o.datatype = "hostname"
o.placeholder = "svcb.example.com."

o = dnsrr:option(Value, "rrnumber", translate("Resource Record Number"))
o.rmempty  = false
o.datatype = "uinteger"
o.placeholder = "64"

o = dnsrr:option(Value, "hexdata", translate("Raw Data"))
o.rmempty  = true
o.datatype = "string"
o.placeholder = "free-form string"

return m