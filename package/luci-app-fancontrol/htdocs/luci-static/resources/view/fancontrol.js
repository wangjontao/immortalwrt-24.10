'use strict';
'require view';
'require fs';
'require form';
'require uci';

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('fancontrol')
		]);
	},

	render: async function () {
		var m, s, o;

		m = new form.Map('fancontrol', _('Fan Control'));
		s = m.section(form.TypedSection, 'settings', _('Settings'));
		s.anonymous = true;

		// 启用开关
		o = s.option(form.Flag, 'enabled', _('Enable'), _('Enable fan speed control'));
		o.rmempty = false;

		/* -----------  兼容新旧 LuCI  ----------- */
		const read = fs.read_file || fs.read;   // 21.02+ 用 read_file，旧版用 read
		/* -------------------------------------- */

		// 温度文件
		o = s.option(form.Value, 'thermal_file', _('Thermal File'), _('Temperature sysfs path'));
		var temp_div = uci.get('fancontrol', 'settings', 'temp_div') || 1000;
		try {
			var tempRaw = await read(uci.get('fancontrol', 'settings', 'thermal_file'));
			o.description = _('Current temperature:') + ' <b>' + (parseInt(tempRaw) / temp_div).toFixed(1) + ' °C</b>';
		} catch (e) {
			o.description = _('Unable to read temperature');
		}

		// 风扇文件
		o = s.option(form.Value, 'fan_file', _('Fan File'), _('Fan PWM sysfs path'));
		try {
			var speedRaw = await read(uci.get('fancontrol', 'settings', 'fan_file'));
			o.description = _('Current speed:') + ' <b>' + parseInt(speedRaw) + '</b>';
		} catch (e) {
			o.description = _('Unable to read fan speed');
		}

		// 参数输入
		o = s.option(form.Value, 'start_speed', _('Initial Speed'), _('Fan speed at start (0-255)'));
		o.placeholder = '77';
		o.datatype = 'range(0,255)';

		o = s.option(form.Value, 'max_speed', _('Max Speed'), _('Maximum fan speed (0-255)'));
		o.placeholder = '204';
		o.datatype = 'range(0,255)';

		o = s.option(form.Value, 'start_temp', _('Start Temperature / °C'), _('Temperature above which fan begins to spin'));
		o.placeholder = '50';
		o.datatype = 'uinteger';

		o = s.option(form.Value, 'temp_div', _('Temperature Divisor'), _('Raw thermal value divider (usually 1000)'));
		o.placeholder = '1000';
		o.datatype = 'uinteger';

		return m.render();
	}
});
