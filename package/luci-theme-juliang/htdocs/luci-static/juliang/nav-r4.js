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
})();
