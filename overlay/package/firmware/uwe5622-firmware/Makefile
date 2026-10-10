include $(TOPDIR)/rules.mk

PKG_NAME:=uwe5622-firmware
PKG_VERSION:=2023.09.02
PKG_RELEASE:=1

PKG_LICENSE:=Redistributable

include $(INCLUDE_DIR)/package.mk

define Package/uwe5622-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=UNISOC UWE5622 (AW859A) firmware
  URL:=https://github.com/armbian/firmware/tree/master/uwe5622
endef

define Build/Compile
endef

define Package/uwe5622-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/uwe5622
	$(CP) ./files/lib/firmware/uwe5622/* $(1)/lib/firmware/uwe5622/
endef

$(eval $(call BuildPackage,uwe5622-firmware))
