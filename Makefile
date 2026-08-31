.PHONY: test build run app install

test:
	swift test

build:
	swift build -c release

run:
	swift run Pace

app: build
	./Scripts/build-app.sh

install: app
	rm -rf "$$HOME/Applications/CodexPace.app"
	mkdir -p "$$HOME/Applications"
	cp -R .build/CodexPace.app "$$HOME/Applications/CodexPace.app"
	@echo "Installed to ~/Applications/CodexPace.app — launch it once manually, then enable Launch at Login in Preferences."
