'use strict';
'require view';
'require form';
'require fs';

return view.extend({
	load: function() {
		return fs.read('/tmp/wan-watchdog.status').catch(function() {
			return null;
		});
	},

	render: function(data) {
		var m = new form.Map('wan-watchdog', _('WAN Watchdog'),
			_('Automatically renew or rebuild the WAN connection when the gateway becomes unavailable.'));
		var s = m.section(form.NamedSection, 'main', 'watchdog');
		var o;

		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable WAN Watchdog'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('When disabled, automatic WAN renewal and restart are stopped.');

		o = s.option(form.DummyValue, '_status', _('Current status'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			var status;

			if (!data)
				return _('No status available');

			try {
				status = JSON.parse(data);
			}
			catch (e) {
				return _('Invalid status');
			}

			return E('code', {}, [
				_('State') + ': ' + (status.state || 'unknown'),
				' / IP: ' + (status.address || '-'),
				' / gateway: ' + (status.gateway || '-'),
				' / failures: ' + (status.failures != null ? status.failures : 0)
			]);
		};

		return m.render();
	}
});
