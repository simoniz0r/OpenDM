PREFIX ?= /usr

all:
		@echo Run \'make install\' to install OpenDM.

install:
		@echo 'Making directories...'
		@mkdir -p $(DESTDIR)$(PREFIX)/bin
		@mkdir -p $(DESTDIR)$(PREFIX)/share/opendm
		@mkdir -p $(DESTDIR)$(PREFIX)/share/applications

		@echo 'Installing OpenDM...'
		@cp -r configs $(DESTDIR)$(PREFIX)/share/opendm/configs
		@chmod +x OpenDM.sh
		@cp -p OpenDM.sh $(DESTDIR)$(PREFIX)/share/opendm/opendm
		@ln -s $(DESTDIR)$(PREFIX)/share/opendm/opendm $(DESTDIR)$(PREFIX)/bin/opendm
		@cp -p opendm.desktop $(DESTDIR)$(PREFIX)/share/applications/opendm.desktop
		@echo 'OpenDM installed!'

uninstall:
		@echo 'Removing files...'
		@rm -f $(DESTDIR)$(PREFIX)/bin/opendm
		@rm -rf $(DESTDIR)$(PREFIX)/share/opendm
		@rm -f $(DESTDIR)$(PREFIX)/share/applications/opendm.desktop
		@echo 'OpenDM uninstalled!'
