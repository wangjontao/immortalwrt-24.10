(function () {
	'use strict';

	var statusUrl = '/cgi-bin/luci/admin/home_status';
	var busy = false;

	function renderEgress(data, wanIp) {
		var root = document.getElementById('juliang-proxy-list');
		if (!root)
			return;
		var primary = data.egress || {};
		var items = Array.isArray(primary.items) && primary.items.length
			? primary.items : [primary];
		root.textContent = '';

		items.slice(0, 4).forEach(function (item, index) {
			var proxy = item.mode === 'proxy';
			var row = document.createElement('div');
			var label = document.createElement('span');
			var ip = document.createElement('strong');
			var location = document.createElement('small');
			row.className = 'juliang-proxy-row';
			if (index === 0) {
				ip.id = 'juliang-proxy-ip';
				location.id = 'juliang-proxy-location';
			}
			label.textContent = item.label || (index === 0 ? '当前代理 IP' : '代理出口');
			ip.textContent = item.ip || (proxy ? '代理出口检测中' : wanIp) || '暂不可用';
			location.textContent = [
				item.country || (proxy ? '代理已启用' : '未知地区'),
				item.mode ? String(item.mode).toUpperCase() : ''
			].filter(Boolean).join(' · ');
			row.appendChild(label);
			row.appendChild(ip);
			row.appendChild(location);
			root.appendChild(row);
		});
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
			renderEgress(data, data.wan?.ip);
		}
		catch (error) {
			renderEgress({
				egress: {
					mode: 'direct',
					items: [{
						mode: 'direct',
						label: '当前代理 IP',
						ip: '暂不可用',
						country: '读取失败'
					}]
				}
			}, '');
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
