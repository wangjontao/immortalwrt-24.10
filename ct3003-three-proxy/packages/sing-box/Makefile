# Pinned official ARM64 release, verified by SHA256; no unverified mirrors.
include $(TOPDIR)/rules.mk
PKG_NAME:=sing-box
PKG_VERSION:=1.14.4
PKG_RELEASE:=1
PKG_SOURCE:=sing-box-1.14.4-linux-arm64-musl.tar.gz
PKG_SOURCE_URL:=https://github.com/SagerNet/sing-box/releases/download/v1.14.4
PKG_HASH:=b95e25f921dc5e17a4cf13327243d1177642c7e35425bf5372862c477c359f56
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
