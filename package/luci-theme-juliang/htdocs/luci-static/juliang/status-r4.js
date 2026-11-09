(function () {
	'use strict';

	var statusUrl = '/cgi-bin/luci/admin/home_status';
	var busy = false;

	function setText(id, value) {
		var element = document.getElementById(id);
		if (element)
			element.textContent = value || '--';
	}

	async function refresh() {
		if (busy || document.hidden)
			return;
		busy = true;
		try {
			var response = await fetch(statusUrl + '?_=' + Date.now(), {
				cache: 'no-store',
				credentials: 'same-origin'
			});
			if (!response.ok)
				throw new Error('HTTP ' + response.status);
			var data = await response.json();
			if (!data.ok)
				throw new Error(data.error || '状态读取失败');
			var egress = data.egress || {};
			setText('juliang-proxy-ip', egress.ip || data.wan?.ip || '暂不可用');
			var location = [egress.country || '未知地区'];
			if (egress.mode)
				location.push(String(egress.mode).toUpperCase());
			setText('juliang-proxy-location', location.join(' · '));
		}
		catch (error) {
			setText('juliang-proxy-ip', '暂不可用');
			setText('juliang-proxy-location', '读取失败');
		}
		finally {
			busy = false;
		}
	}

	refresh();
	setInterval(refresh, 15000);
	document.addEventListener('visibilitychange', function () {
		if (!document.hidden)
			refresh();
	});
})();
