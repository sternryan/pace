.PHONY: test build run app install cli install-cli

test:
	swift test

build:
	swift build -c release

run:
	swift run Pace

app: build
	./Scripts/build-app.sh

install: app
	rm -rf "$$HOME/Applications/Pace.app"
	mkdir -p "$$HOME/Applications"
	cp -R .build/Pace.app "$$HOME/Applications/Pace.app"
	@echo "Installed to ~/Applications/Pace.app — launch it once manually, then enable Launch at Login in Preferences."

cli:
	swift build -c release --product pace-cli

install-cli: cli
	mkdir -p "$$HOME/.local/bin"
	cp .build/release/pace-cli "$$HOME/.local/bin/pace"
	@echo "Installed ~/.local/bin/pace"
