'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	__init__() {
		this.bindShell();
		ui.menu.load().then(L.bind(this.render, this));
	},

	bindShell() {
		var body = document.body;
		var button = document.getElementById('juliang-menu-button');
		var scrim = document.getElementById('juliang-scrim');
		var revision = '285-2';

		try {
			var key = 'luci-session-store';
			var sessions = JSON.parse(sessionStorage.getItem(key) || '{}');

			Object.keys(sessions).forEach(function (session) {
				var entry = sessions[session];

				if (entry && typeof entry === 'object' && entry.juliangMenuRevision !== revision) {
					delete entry.menu;
					entry.juliangMenuRevision = revision;
				}
			});

			sessionStorage.setItem(key, JSON.stringify(sessions));
		}
		catch (error) {
			/* Session storage can be unavailable in private browsing. */
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
	},

	isCurrent(name) {
		return Array.isArray(L.env.dispatchpath) && L.env.dispatchpath.indexOf(name) !== -1;
	},

	displayTitle(title) {
		const labels = {
			'System': '系统',
			'Network': '网络',
			'Log out': '退出',
			'无线设备': '无线设备管理'
		};

		return labels[title] || title;
	},

	render(tree) {
		let node = tree;
		let url = '';

		this.renderModeMenu(tree);

		for (var i = 0; i < 3 && node; i++) {
			node = node.children[L.env.dispatchpath[i]];
			url = url + (url ? '/' : '') + L.env.dispatchpath[i];
		}

		if (node)
			this.renderTabMenu(node, url);
	},

	renderTabMenu(tree, url, level) {
		const container = document.querySelector('#tabmenu');
		const ul = E('ul', { 'class': 'tabs' });
		const children = ui.menu.getChildren(tree);
		let activeNode = null;

		children.forEach(child => {
			const isActive = (L.env.dispatchpath[3 + (level || 0)] == child.name);
			const activeClass = isActive ? ' active' : '';
			const className = 'tabmenu-item-' + child.name + activeClass;

			ul.appendChild(E('li', { 'class': className }, [
				E('a', { 'href': L.url(url, child.name) }, [ _(this.displayTitle(child.title)) ])
			]));

			if (isActive)
				activeNode = child;
		});

		if (ul.children.length == 0)
			return E([]);

		container.appendChild(ul);
		container.style.display = '';

		if (activeNode)
			this.renderTabMenu(activeNode, url + '/' + activeNode.name, (level || 0) + 1);

		return ul;
	},

	renderMainMenu(tree, url, level) {
		const ul = level ? E('ul', { 'class': 'dropdown-menu' }) : document.querySelector('#topmenu');
		const children = ui.menu.getChildren(tree);
		const active = this.isCurrent.bind(this);

		if (children.length == 0 || level > 1)
			return E([]);

		children.forEach(child => {
			const submenu = this.renderMainMenu(child, url + '/' + child.name, (level || 0) + 1);
			const hasChildren = !!submenu.firstElementChild;
			const isOpen = !level && hasChildren && active(child.name);
			const subclass = [
				(!level && hasChildren) ? 'dropdown' : '',
				active(child.name) ? 'active' : '',
				isOpen ? 'open' : ''
			].filter(Boolean).join(' ');
			const linkclass = (!level && hasChildren) ? 'menu' : '';
			const linkurl = hasChildren ? '#' : L.url(url, child.name);
			const link = E('a', { 'class': linkclass, 'href': linkurl }, [
				E('span', { 'class': 'juliang-nav-glyph', 'aria-hidden': 'true' }),
				E('span', { 'class': 'juliang-nav-title' }, [ _(this.displayTitle(child.title)) ]),
				hasChildren ? E('span', { 'class': 'juliang-nav-chevron', 'aria-hidden': 'true' }, ['›']) : E([])
			]);

			const li = E('li', { 'class': subclass }, [ link, submenu ]);

			if (!level && hasChildren) {
				link.setAttribute('aria-expanded', String(isOpen));
				submenu.setAttribute('aria-hidden', String(!isOpen));
				link.addEventListener('click', function (event) {
					event.preventDefault();
					const opening = !li.classList.contains('open');

					document.querySelectorAll('#topmenu > li.dropdown.open').forEach(function (item) {
						if (item === li)
							return;

						item.classList.remove('open');
						var toggle = item.querySelector(':scope > a');
						var children = item.querySelector(':scope > .dropdown-menu');

						if (toggle)
							toggle.setAttribute('aria-expanded', 'false');
						if (children)
							children.setAttribute('aria-hidden', 'true');
					});

					li.classList.toggle('open', opening);
					link.setAttribute('aria-expanded', String(opening));
					submenu.setAttribute('aria-hidden', String(!opening));
				});
			}

			ul.appendChild(li);
		});

		ul.style.display = '';
		return ul;
	},

	renderModeMenu(tree) {
		const ul = document.querySelector('#modemenu');
		const children = ui.menu.getChildren(tree);

		if (!ul)
			return;

		children.forEach((child, index) => {
			const isActive = L.env.requestpath.length
				? child.name === L.env.requestpath[0]
				: index === 0;

			ul.appendChild(E('li', { 'class': isActive ? 'active' : '' }, [
				E('a', { 'href': L.url(child.name) }, [ _(child.title) ])
			]));

			if (isActive)
				this.renderMainMenu(child, child.name);
		});

		if (ul.children.length > 1)
			ul.style.display = '';
	}
});
