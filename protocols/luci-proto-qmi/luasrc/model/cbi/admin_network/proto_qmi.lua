-- Copyright 2016 David Thornley <david.thornley@touchstargroup.com>
-- Licensed to the public under the Apache License 2.0.

local map, section, net = ...

local device, apn, pincode, username, password
local auth, ipv6


device = section:taboption("general", Value, "device", translate("Modem device"))
device.rmempty = false

local device_suggestions = nixio.fs.glob("/dev/cdc-wdm*")

if device_suggestions then
	local node
	for node in device_suggestions do
		device:value(node)
	end
end


apn = section:taboption("general", Value, "apn", translate("APN"))

if luci.model.network:has_ipv6() then
	v6apn = section:taboption("general", Value, "v6apn", translate("IPv6 APN"))
	v6apn:depends("pdptype", "ipv4v6")
end

pincode = section:taboption("general", Value, "pincode", translate("PIN"))
pincode.datatype = 'and(uinteger,minlength(4),maxlength(8))'

auth = section:taboption("general", Value, "auth", translate("Authentication Type"))
auth:value("both", "PAP/CHAP (both)")
auth:value("pap", "PAP")
auth:value("chap", "CHAP")
auth:value("none", "NONE")
auth.default = "none"

username = section:taboption("general", Value, "username", translate("PAP/CHAP username"))

password = section:taboption("general", Value, "password", translate("PAP/CHAP password"))
password.password = true

if luci.model.network:has_ipv6() then
    ipv6 = section:taboption("advanced", Flag, "ipv6", translate("Enable IPv6 negotiation"))
    ipv6.default = ipv6.disabled
end

delay = section:taboption("advanced", Value, "delay", translate("Modem init timeout"), translate("Maximum amount of seconds to wait for the modem to become ready"))
delay.placeholder = "10"
delay.datatype = "min(1)"

mtu = section:taboption("advanced", Value, "mtu", translate("Override MTU"))
mtu.placeholder = "1500"
mtu.datatype    = "max(9200)"

pdptype = section:taboption('general', ListValue, 'pdptype', translate('PDP Type'))
pdptype:value('ipv4v6', 'IPv4/IPv6')
pdptype:value('ipv4', 'IPv4')
pdptype:value('ipv6', 'IPv6')
pdptype.default = 'ipv4v6'

if luci.model.network:has_ipv6() then
    v6profile = section:taboption("advanced", Value, "v6profile", translate("IPv6 APN profile index"))
    v6profile.placeholder = "1"
    v6profile.datatype = "uinteger"
	v6profile:depends("pdptype", "ipv4v6")
end
