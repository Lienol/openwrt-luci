'use strict';
'require baseclass';
'require fs';
'require rpc';
'require uci';

var callGetUnixtime = rpc.declare({
	object: 'luci',
	method: 'getUnixtime',
	expect: { result: 0 }
});

var callLuciVersion = rpc.declare({
	object: 'luci',
	method: 'getVersion'
});

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

return baseclass.extend({
	title: _('System'),

	load: function() {
		return callSystemBoard().then(function (boardinfo) {
			return Promise.all([
				boardinfo,
				L.resolveDefault(callSystemInfo(), {}),
				L.resolveDefault(callLuciVersion(), { revision: _('unknown version'), branch: 'LuCI' }),
				L.resolveDefault(callGetUnixtime(), 0),
				L.resolveDefault(fs.exec_direct('/sbin/cpuinfo'), ''),
				boardinfo.system.startsWith("ARM") ? L.resolveDefault(fs.exec_direct('/sbin/usage'), '') : L.resolveDefault(fs.exec_direct('/sbin/luci-mod-status-cpu_free'), ''),
				uci.load('system')
			]);
		});
	},

	render: function(data) {
		var boardinfo   = data[0],
		    systeminfo  = data[1],
		    luciversion = data[2],
		    unixtime    = data[3];

		luciversion = luciversion.branch + ' ' + luciversion.revision;

		var datestr = null;

		if (unixtime) {
			var date = new Date(unixtime * 1000),
				zn = uci.get('system', '@system[0]', 'zonename')?.replaceAll(' ', '_') || 'UTC',
				ts = uci.get('system', '@system[0]', 'clock_timestyle') || 0,
				hc = uci.get('system', '@system[0]', 'clock_hourcycle') || 0;

			datestr = new Intl.DateTimeFormat(undefined, {
				dateStyle: 'medium',
				timeStyle: (ts == 0) ? 'long' : 'full',
				hourCycle: (hc == 0) ? undefined : hc,
				timeZone: zn
			}).format(date);
		}

		var fields = [
			_('Hostname'),         boardinfo.hostname,
			_('Model'),            boardinfo.model,
			_('Architecture'),     boardinfo.system,
			_('Target Platform'),  (L.isObject(boardinfo.release) ? boardinfo.release.target : ''),
			_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),
			_('Kernel Version'),   boardinfo.kernel,
			_('Local Time'),       datestr,
			_('Uptime'),           systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Load Average'),     Array.isArray(systeminfo.load) ? '%.2f, %.2f, %.2f'.format(
				systeminfo.load[0] / 65535.0,
				systeminfo.load[1] / 65535.0,
				systeminfo.load[2] / 65535.0
			) : null
		];

		if (data[4]) {
			var cpuinfo = data[4];
			//fields[4] = _('CPU Info')
			//fields[5] = cpuinfo
			if ((L.isObject(boardinfo.release) ? boardinfo.release.target : '').startsWith("x86")) {
				fields[5] = fields[5] + " (" + cpuinfo + ")"
			} else if (boardinfo.system.startsWith("ARM")) {
				fields[5] = cpuinfo
			}
		}

		if (data[5]) {
			var cpu_free = data[5];
			fields.push(_('CPU Used'))
			if (boardinfo.system.startsWith("ARM")) {
				fields.push(cpu_free)
			} else {
				fields.push((100 - cpu_free) + "%")
			}
		}

		var table = E('table', { 'class': 'table' });

		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				E('td', { 'class': 'td left' }, [ (fields[i + 1] != null) ? fields[i + 1] : '?' ])
			]));
		}

		return table;
	}
});
