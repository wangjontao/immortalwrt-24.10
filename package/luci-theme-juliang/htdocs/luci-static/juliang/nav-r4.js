(function () {
	'use strict';

	var body = document.body;
	var button = document.getElementById('juliang-menu-button');
	var scrim = document.getElementById('juliang-scrim');
	var items = Array.from(document.querySelectorAll('#topmenu > li'));

	function closeOthers(current) {
		items.forEach(function (item) {
			if (item === current || !item.classList.contains('dropdown'))
				return;
			item.classList.remove('open');
			var link = item.querySelector(':scope > a');
			var menu = item.querySelector(':scope > .dropdown-menu');
			if (link)
				link.setAttribute('aria-expanded', 'false');
			if (menu)
				menu.setAttribute('aria-hidden', 'true');
		});
	}

	items.forEach(function (item) {
		var link = item.querySelector(':scope > a');
		var menu = item.querySelector(':scope > .dropdown-menu');
		if (!link || !menu)
			return;
		link.setAttribute('aria-expanded', 'false');
		menu.setAttribute('aria-hidden', 'true');
		link.addEventListener('click', function (event) {
			event.preventDefault();
			var opening = !item.classList.contains('open');
			closeOthers(item);
			item.classList.toggle('open', opening);
			link.setAttribute('aria-expanded', String(opening));
			menu.setAttribute('aria-hidden', String(!opening));
		});
	});

	var path = window.location.pathname;
	var active = items.find(function (item) {
		return path.indexOf(item.dataset.navPrefix || '\0') === 0;
	});
	if (active) {
		active.classList.add('active');
		if (active.classList.contains('dropdown')) {
			active.classList.add('open');
			var activeLink = active.querySelector(':scope > a');
			var activeMenu = active.querySelector(':scope > .dropdown-menu');
			if (activeLink)
				activeLink.setAttribute('aria-expanded', 'true');
			if (activeMenu)
				activeMenu.setAttribute('aria-hidden', 'false');
		}
	}

	if (button)
		button.addEventListener('click', function () {
			body.classList.toggle('nav-open');
		});
	if (scrim)
		scrim.addEventListener('click', function () {
			body.classList.remove('nav-open');
		});
	document.addEventListener('keydown', function (event) {
		if (event.key === 'Escape')
			body.classList.remove('nav-open');
	});

	function renderPageTabs() {
		var container = document.getElementById('tabmenu');
		var path = window.L && L.env && L.env.dispatchpath;
		if (!container || !path || path.length < 3 || !window.L.require)
			return;

		L.require('ui').then(function (ui) {
			ui.menu.load().then(function (tree) {
				var node = tree;
				var url = '';
				var index;

				for (index = 0; index < 3 && node; index++) {
					node = node.children ? node.children[path[index]] : null;
					url += (url ? '/' : '') + path[index];
				}
				if (!node)
					return;

				function appendLevel(parent, baseUrl, level) {
					var children = ui.menu.getChildren(parent);
					if (!children.length)
						return;

					var list = document.createElement('ul');
					var activeNode = null;
					list.className = 'tabs';
					children.forEach(function (child) {
						var active = path[3 + level] === child.name;
						var item = document.createElement('li');
						var link = document.createElement('a');
						item.className = 'tabmenu-item-' + child.name +
							(active ? ' active' : '');
						link.href = L.url(baseUrl, child.name);
						link.textContent = typeof _ === 'function'
							? _(child.title) : child.title;
						item.appendChild(link);
						list.appendChild(item);
						if (active)
							activeNode = child;
					});
					container.appendChild(list);
					container.style.display = '';
					if (activeNode)
						appendLevel(activeNode, baseUrl + '/' + activeNode.name, level + 1);
				}

				container.textContent = '';
				appendLevel(node, url, 0);
			});
		});
	}

	var prefetched = Object.create(null);

	function prefetchLink(link) {
		if (!link || link.target || link.hasAttribute('download') ||
		    link.origin !== window.location.origin ||
		    navigator.connection?.saveData ||
		    prefetched[link.href])
			return;
		prefetched[link.href] = true;
		var request = document.createElement('link');
		request.rel = 'prefetch';
		request.as = 'document';
		request.href = link.href;
		document.head.appendChild(request);
	}

	function linkFromEvent(event) {
		var target = event.target;
		return target && target.closest
			? target.closest('a[href]') : null;
	}

	document.addEventListener('pointerover', function (event) {
		prefetchLink(linkFromEvent(event));
	});
	document.addEventListener('focusin', function (event) {
		prefetchLink(linkFromEvent(event));
	});
	document.addEventListener('click', function (event) {
		var link = linkFromEvent(event);
		if (!link || event.defaultPrevented || event.button !== 0 ||
		    event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
		    link.target || link.origin !== window.location.origin ||
		    link.hash && link.pathname === window.location.pathname)
			return;
		body.classList.add('juliang-navigating');
	});

	renderPageTabs();
})();
