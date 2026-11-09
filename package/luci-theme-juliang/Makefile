#
# JuLiang OS v1.3 LuCI theme
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=JuLiang OS Network Console Theme
LUCI_DEPENDS:=+luci-base

PKG_VERSION:=1.3
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=JuLiang OS

define Package/luci-theme-juliang/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.JuLiang
	if [ "$$(uci -q get luci.main.mediaurlbase)" = "/luci-static/juliang" ]; then
		uci -q set luci.main.mediaurlbase=/luci-static/bootstrap
	fi
	uci commit luci
}
endef

define Package/luci-theme-juliang/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
uci -q set luci.themes.JuLiang='/luci-static/juliang'
uci -q set luci.main.mediaurlbase='/luci-static/juliang'
uci -q set luci.main.lang='zh_cn'
uci -q commit luci
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
