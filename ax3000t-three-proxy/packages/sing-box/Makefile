# Pinned official ARM64 release, verified by SHA256; no unverified mirrors.
include $(TOPDIR)/rules.mk
PKG_NAME:=sing-box
PKG_VERSION:=1.14.4
PKG_RELEASE:=1
PKG_SOURCE:=sing-box-1.14.4-linux-arm64.tar.gz
PKG_SOURCE_URL:=https://github.com/SagerNet/sing-box/releases/download/v1.14.4
PKG_HASH:=436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-prebuilt
PKG_LICENSE:=GPL-3.0-only
include $(INCLUDE_DIR)/package.mk

define Package/sing-box
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Official sing-box ARM64 1.14.4
  DEPENDS:=@aarch64 +ca-bundle +kmod-tun
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/sing-box/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sing-box $(1)/usr/bin/sing-box
endef

$(eval $(call BuildPackage,sing-box))
